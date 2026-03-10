#!/usr/bin/env bash
# scripts/lib/validate.sh
# Pre-flight checks (before setup) and post-setup validation
# Sourced by setup.sh — do not execute directly

# Minimum required Docker Compose version (v2)
readonly MIN_COMPOSE_MAJOR=2

# ── Pre-flight ─────────────────────────────────────────────────────────────────
# Run before any changes are made. Abort early if requirements are not met.

validate::preflight() {
  print_section "Pre-flight checks"

  local errors=0

  # ── Docker ──────────────────────────────────────────────────────────────────
  if ! command -v docker &>/dev/null; then
    print_error "docker not found — install Docker Desktop or Docker Engine"
    (( errors++ ))
  else
    print_ok "docker found: $(docker --version 2>/dev/null | head -1)"
  fi

  # ── Docker daemon ───────────────────────────────────────────────────────────
  if command -v docker &>/dev/null; then
    if ! docker info &>/dev/null; then
      print_error "Docker daemon is not running — start Docker and retry"
      (( errors++ ))
    else
      print_ok "Docker daemon is running"
    fi
  fi

  # ── Docker Compose v2 ───────────────────────────────────────────────────────
  if command -v docker &>/dev/null; then
    local compose_version
    compose_version=$(docker compose version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if [ -z "${compose_version}" ]; then
      print_error "Docker Compose v2 not found (requires 'docker compose', not 'docker-compose')"
      (( errors++ ))
    else
      local compose_major
      compose_major=$(echo "${compose_version}" | cut -d. -f1)
      if [ "${compose_major}" -lt "${MIN_COMPOSE_MAJOR}" ]; then
        print_error "Docker Compose v${compose_version} found — v2+ required"
        (( errors++ ))
      else
        print_ok "docker compose found: v${compose_version}"
      fi
    fi
  fi

  # ── /dev/urandom ────────────────────────────────────────────────────────────
  if [ ! -r /dev/urandom ]; then
    print_error "/dev/urandom not readable — cannot generate passwords"
    (( errors++ ))
  else
    print_ok "/dev/urandom available (password generation)"
  fi

  # ── Required project files ──────────────────────────────────────────────────
  local required_files=(
    "docker-compose.yml"
    "docker-compose.monitoring.yml"
    ".env.example"
    "redis/redis.conf"
    "rabbitmq/rabbitmq.conf"
    "rabbitmq/enabled_plugins"
    "prometheus/prometheus.yml"
    "grafana/provisioning/datasources/datasources.yml"
    "grafana/provisioning/dashboards/dashboards.yml"
  )

  for f in "${required_files[@]}"; do
    if [ ! -f "${PROJECT_ROOT}/${f}" ]; then
      print_error "Missing required file: ${f}"
      (( errors++ ))
    fi
  done

  if [ "${errors}" -eq 0 ]; then
    print_ok "All required project files found"
  fi

  # ── curl (optional but recommended for dashboards) ──────────────────────────
  if ! command -v curl &>/dev/null; then
    print_warn "curl not found — Grafana dashboards won't be downloaded automatically"
  else
    print_ok "curl found (Grafana dashboard download)"
  fi

  # ── Abort if critical errors ────────────────────────────────────────────────
  if [ "${errors}" -gt 0 ]; then
    print_fatal "${errors} pre-flight check(s) failed. Fix the issues above and retry."
  fi

  print_ok "All pre-flight checks passed"
}

# ── Post-setup validation ──────────────────────────────────────────────────────
# Run after the stack is started. Checks that everything is healthy.

validate::post_setup() {
  print_section "Post-setup validation"

  print_info "Waiting for services to become healthy (up to 90 seconds)..."

  local deadline=$(( $(date +%s) + 90 ))
  local all_healthy=false

  while [ "$(date +%s)" -lt "${deadline}" ]; do
    local unhealthy
    unhealthy=$(
      docker compose \
        -f "${PROJECT_ROOT}/docker-compose.yml" \
        -f "${PROJECT_ROOT}/docker-compose.monitoring.yml" \
        ps --format json 2>/dev/null \
      | grep -c '"Health":"unhealthy"' || true
    )
    local starting
    starting=$(
      docker compose \
        -f "${PROJECT_ROOT}/docker-compose.yml" \
        -f "${PROJECT_ROOT}/docker-compose.monitoring.yml" \
        ps --format json 2>/dev/null \
      | grep -c '"Health":"starting"' || true
    )

    if [ "${unhealthy}" -eq 0 ] && [ "${starting}" -eq 0 ]; then
      all_healthy=true
      break
    fi

    printf "."
    sleep 5
  done
  echo ""

  if [ "${all_healthy}" = false ]; then
    print_warn "Some services may still be starting or unhealthy"
    print_info "Check status with:"
    print_info "  docker compose -f docker-compose.yml -f docker-compose.monitoring.yml ps"
  fi

  # ── Service-level checks ────────────────────────────────────────────────────
  validate::_check_redis
  validate::_check_rabbitmq
  validate::_check_prometheus
  validate::_check_exporters
}

# ── Individual service checks ──────────────────────────────────────────────────

validate::_check_redis() {
  # Redis: expect NOAUTH (ACL active, server running) or PONG
  local response
  response=$(docker exec redis redis-cli ping 2>&1 || true)
  if echo "${response}" | grep -qE "PONG|NOAUTH"; then
    print_ok "Redis is responding (ACL active)"
  else
    print_warn "Redis health check inconclusive — response: ${response}"
    print_info "Check logs: docker compose logs redis"
  fi
}

validate::_check_rabbitmq() {
  local result
  result=$(docker exec rabbitmq rabbitmq-diagnostics -q ping 2>&1 || true)
  if echo "${result}" | grep -qi "succeeded\|pong\|ok"; then
    print_ok "RabbitMQ is responding"
  else
    print_warn "RabbitMQ health check inconclusive"
    print_info "Check logs: docker compose logs rabbitmq"
  fi
}

validate::_check_prometheus() {
  # Give Prometheus a moment to finish loading targets
  sleep 3
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    "http://localhost:9090/-/ready" 2>/dev/null || echo "000")
  if [ "${http_code}" = "200" ]; then
    print_ok "Prometheus is ready — http://localhost:9090"
  else
    print_warn "Prometheus not yet ready (HTTP ${http_code}) — may still be starting"
  fi
}

validate::_check_exporters() {
  # redis_exporter
  local redis_up
  redis_up=$(curl -s "http://localhost:9121/metrics" 2>/dev/null \
    | grep "^redis_up " | awk '{print $2}' || echo "")
  if [ "${redis_up}" = "1" ]; then
    print_ok "redis_exporter is scraping Redis successfully"
  else
    print_warn "redis_exporter: redis_up=${redis_up:-unknown}"
    print_info "Verify REDIS_EXPORTER_PASSWORD matches appuser password in redis/users.acl"
  fi

  # RabbitMQ Prometheus endpoint
  local rmq_code
  rmq_code=$(curl -s -o /dev/null -w "%{http_code}" \
    "http://localhost:15692/metrics" 2>/dev/null || echo "000")
  if [ "${rmq_code}" = "200" ]; then
    print_ok "RabbitMQ Prometheus endpoint is reachable"
  else
    print_warn "RabbitMQ Prometheus endpoint HTTP ${rmq_code}"
  fi
}

# ── Print access summary ───────────────────────────────────────────────────────

validate::print_access_summary() {
  echo ""
  echo "  ${_BOLD}Stack is up — access your services:${_RESET}"
  echo "  ${_CYAN}────────────────────────────────────────────────────────${_RESET}"
  printf "  %-22s %s\n" "RabbitMQ UI:"     "http://localhost:15672"
  printf "  %-22s %s\n" "RedisInsight:"    "http://localhost:5540"
  printf "  %-22s %s\n" "RabbitScout:"     "http://localhost:3001"
  printf "  %-22s %s\n" "Prometheus:"      "http://localhost:9090"
  printf "  %-22s %s\n" "Grafana:"         "http://localhost:3002"
  echo "  ${_CYAN}────────────────────────────────────────────────────────${_RESET}"
  echo ""
  print_info "All credentials are in: .env and redis/users.acl"
  print_info "Prometheus targets:     http://localhost:9090/targets"
  echo ""
}
