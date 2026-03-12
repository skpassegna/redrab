#!/usr/bin/env bash
# scripts/lib/validate.sh
# Read-only checks — never modifies files, never starts containers
# Sourced by validate.sh — do not execute directly

# ── Pre-flight: verify tools and project files exist ──────────────────────────
# Run before setup.sh to catch missing requirements early

validate::preflight() {
  print_section "Pre-flight checks"

  local errors=0

  # docker
  if ! command -v docker &>/dev/null; then
    print_error "docker not found"
    print_info  "Install Docker Desktop: https://www.docker.com/products/docker-desktop"
    (( errors++ ))
  else
    print_ok "docker: $(docker --version 2>/dev/null)"
  fi

  # Docker daemon
  if command -v docker &>/dev/null && ! docker info &>/dev/null; then
    print_error "Docker daemon is not running — start Docker and retry"
    (( errors++ ))
  elif command -v docker &>/dev/null; then
    print_ok "Docker daemon is running"
  fi

  # Docker Compose v2
  if command -v docker &>/dev/null; then
    local cv
    cv=$(docker compose version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if [ -z "${cv}" ]; then
      print_error "Docker Compose v2 not found ('docker compose' plugin required)"
      (( errors++ ))
    elif [ "$(echo "${cv}" | cut -d. -f1)" -lt 2 ]; then
      print_error "Docker Compose v${cv} found — v2+ required"
      (( errors++ ))
    else
      print_ok "docker compose: v${cv}"
    fi
  fi

  # /dev/urandom (needed by setup.sh for password generation)
  if [ ! -r /dev/urandom ]; then
    print_error "/dev/urandom not readable"
    (( errors++ ))
  else
    print_ok "/dev/urandom available"
  fi

  # Required project files
  local required=(
    "docker-compose.yml"
    "docker-compose.monitoring.yml"
    ".env.example"
    "redis/redis.conf"
    "redis/users.acl"
    "rabbitmq/rabbitmq.conf"
    "rabbitmq/enabled_plugins"
    "prometheus/prometheus.yml"
    "grafana/provisioning/datasources/datasources.yml"
    "grafana/provisioning/dashboards/dashboards.yml"
  )

  local missing=0
  for f in "${required[@]}"; do
    if [ ! -f "${PROJECT_ROOT}/${f}" ]; then
      print_error "Missing: ${f}"
      (( missing++ ))
      (( errors++ ))
    fi
  done
  [ "${missing}" -eq 0 ] && print_ok "All required project files present"

  # curl (optional, for dashboards)
  if ! command -v curl &>/dev/null; then
    print_warn "curl not found — Grafana dashboards won't be auto-downloaded"
  fi

  [ "${errors}" -gt 0 ] && print_fatal "${errors} pre-flight check(s) failed"
  print_ok "Pre-flight passed"
}

# ── Config validation: read .env and check file sync ─────────────────────────
# Does not modify anything

validate::config() {
  print_section "Configuration validation"

  local env_file="${PROJECT_ROOT}/.env"
  local acl_file="${PROJECT_ROOT}/redis/users.acl"

  # .env
  if [ ! -f "${env_file}" ]; then
    print_error ".env not found — run ./setup.sh first"
    return 1
  fi
  print_ok ".env present"

  # Check for remaining CHANGE_ME placeholders
  local placeholders
  placeholders=$(grep "CHANGE_ME" "${env_file}" 2>/dev/null || true)
  if [ -n "${placeholders}" ]; then
    print_warn "Placeholder passwords still in .env — run ./setup.sh to generate real passwords"
    echo "${placeholders}" | while read -r line; do
      print_info "  → ${line}"
    done
  else
    print_ok "No placeholder passwords in .env"
  fi

  # users.acl
  if [ ! -f "${acl_file}" ]; then
    print_error "redis/users.acl not found"
    return 1
  fi

  if grep -q "CHANGE_ME" "${acl_file}"; then
    print_warn "redis/users.acl still has placeholder passwords — run ./setup.sh"
  else
    print_ok "redis/users.acl has no placeholders"
  fi

  # Check default user is disabled
  if grep -q "user default off" "${acl_file}"; then
    print_ok "redis/users.acl: default user is disabled (correct)"
  else
    print_warn "redis/users.acl: 'user default off' not found — check ACL config"
  fi

  # Grafana dashboards
  local dash_dir="${PROJECT_ROOT}/grafana/provisioning/dashboards"
  for f in "redis.json" "rabbitmq-overview.json"; do
    if [ -f "${dash_dir}/${f}" ]; then
      print_ok "Grafana dashboard present: ${f}"
    else
      print_warn "Grafana dashboard missing: ${f} — run ./setup.sh --dashboards"
    fi
  done
}

# ── Runtime validation: checks running containers ─────────────────────────────
# Read-only — only inspects state, never starts or restarts anything

validate::runtime() {
  print_section "Runtime validation"

  # Container status
  local compose_ps
  compose_ps=$(docker compose \
    -f "${PROJECT_ROOT}/docker-compose.yml" \
    -f "${PROJECT_ROOT}/docker-compose.monitoring.yml" \
    ps 2>/dev/null) || {
    print_error "Could not read container status — is the stack running?"
    print_info  "Start with: docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d"
    return 1
  }

  # Check each expected service
  local services=("redis" "rabbitmq" "redis-exporter" "redisinsight" "rabbitscout" "prometheus" "grafana")
  for svc in "${services[@]}"; do
    if echo "${compose_ps}" | grep -q "${svc}"; then
      if echo "${compose_ps}" | grep "${svc}" | grep -qE "Up|running|healthy"; then
        print_ok "${svc}: running"
      elif echo "${compose_ps}" | grep "${svc}" | grep -q "unhealthy"; then
        print_warn "${svc}: unhealthy — check logs: docker compose logs ${svc}"
      else
        print_warn "${svc}: status unknown"
      fi
    else
      print_error "${svc}: not found — may not be started"
    fi
  done

  # Redis: expect PONG or NOAUTH (ACL active = Redis running correctly)
  print_section "Service health"

  local redis_response
  redis_response=$(docker exec redis redis-cli ping 2>&1 || true)
  if echo "${redis_response}" | grep -qE "PONG|NOAUTH"; then
    print_ok "Redis: responding (${redis_response})"
  else
    print_warn "Redis: unexpected response: ${redis_response}"
    print_info "Check logs: docker compose logs redis"
  fi

  # RabbitMQ
  local rmq_result
  rmq_result=$(docker exec rabbitmq rabbitmq-diagnostics -q ping 2>&1 || true)
  if echo "${rmq_result}" | grep -qiE "succeeded|pong"; then
    print_ok "RabbitMQ: responding"
  else
    print_warn "RabbitMQ: unexpected response: ${rmq_result}"
    print_info "Check logs: docker compose logs rabbitmq"
  fi

  # Prometheus
  local prom_code
  prom_code=$(curl -s -o /dev/null -w "%{http_code}" \
    "http://localhost:9090/-/ready" 2>/dev/null || echo "000")
  if [ "${prom_code}" = "200" ]; then
    print_ok "Prometheus: ready (http://localhost:9090)"
  else
    print_warn "Prometheus: HTTP ${prom_code} — may still be starting"
  fi

  # redis_exporter: redis_up metric
  local redis_up
  redis_up=$(curl -s "http://localhost:9121/metrics" 2>/dev/null \
    | grep "^redis_up " | awk '{print $2}' || echo "")
  if [ "${redis_up}" = "1" ]; then
    print_ok "redis_exporter: redis_up=1 (scraping successfully)"
  else
    print_warn "redis_exporter: redis_up=${redis_up:-unreachable}"
    print_info "Verify REDIS_EXPORTER_PASSWORD in .env matches appuser in redis/users.acl"
  fi

  # RabbitMQ Prometheus endpoint
  local rmq_prom_code
  rmq_prom_code=$(curl -s -o /dev/null -w "%{http_code}" \
    "http://localhost:15692/metrics" 2>/dev/null || echo "000")
  if [ "${rmq_prom_code}" = "200" ]; then
    print_ok "RabbitMQ Prometheus endpoint: reachable"
  else
    print_warn "RabbitMQ Prometheus endpoint: HTTP ${rmq_prom_code}"
  fi

  # Access summary
  echo ""
  echo "  ${_BOLD}Web interfaces${_RESET}"
  echo "  ${_CYAN}──────────────────────────────────────────────────${_RESET}"
  printf "  %-22s %s\n" "RabbitMQ UI:"  "http://localhost:15672"
  printf "  %-22s %s\n" "RedisInsight:" "http://localhost:5540"
  printf "  %-22s %s\n" "RabbitScout:"  "http://localhost:3001"
  printf "  %-22s %s\n" "Prometheus:"   "http://localhost:9090"
  printf "  %-22s %s\n" "Grafana:"      "http://localhost:3002"
  echo "  ${_CYAN}──────────────────────────────────────────────────${_RESET}"
  echo ""
}
