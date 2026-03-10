#!/usr/bin/env bash
# scripts/lib/passwords.sh
# Secure password generation and injection into .env and redis/users.acl
# Sourced by setup.sh — do not execute directly
#
# Password policy: alphanumeric only [A-Za-z0-9], 32 characters
# Rationale: special characters cause parsing issues in .env files,
# Redis ACL inline format, and AMQP URI percent-encoding.

# ── Generation ─────────────────────────────────────────────────────────────────

# Generate a single secure alphanumeric password (32 chars)
# Uses /dev/urandom filtered through tr — works on macOS and Linux
passwords::generate() {
  LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32
}

# ── Main entry point ───────────────────────────────────────────────────────────

passwords::setup() {
  print_section "Generating and applying passwords"

  local env_file="${PROJECT_ROOT}/.env"
  local env_example="${PROJECT_ROOT}/.env.example"
  local acl_file="${PROJECT_ROOT}/redis/users.acl"

  # ── Ensure .env exists ──────────────────────────────────────────────────────
  if [ ! -f "${env_file}" ]; then
    if [ -f "${env_example}" ]; then
      cp "${env_example}" "${env_file}"
      print_ok ".env created from .env.example"
    else
      print_fatal ".env.example not found — cannot create .env"
    fi
  else
    print_info ".env already exists — passwords will be regenerated"
    # Backup existing .env
    local backup="${env_file}.backup.$(date +%Y%m%d-%H%M%S)"
    cp "${env_file}" "${backup}"
    print_ok "Existing .env backed up to: $(basename "${backup}")"
  fi

  # ── Generate passwords ──────────────────────────────────────────────────────
  local pw_redis_admin;    pw_redis_admin=$(passwords::generate)
  local pw_redis_app;      pw_redis_app=$(passwords::generate)
  local pw_redis_readonly; pw_redis_readonly=$(passwords::generate)
  local pw_rabbitmq;       pw_rabbitmq=$(passwords::generate)
  local pw_grafana;        pw_grafana=$(passwords::generate)

  # redis_exporter uses the appuser password
  local pw_redis_exporter="${pw_redis_app}"

  print_ok "All passwords generated (32-char alphanumeric)"

  # ── Inject into .env ────────────────────────────────────────────────────────
  passwords::_set_env "REDIS_PASSWORD"           "${pw_redis_admin}"    "${env_file}"
  passwords::_set_env "REDIS_EXPORTER_PASSWORD"  "${pw_redis_exporter}" "${env_file}"
  passwords::_set_env "RABBITMQ_PASSWORD"        "${pw_rabbitmq}"       "${env_file}"
  passwords::_set_env "GF_ADMIN_PASSWORD"        "${pw_grafana}"        "${env_file}"

  print_ok ".env updated"

  # ── Inject into redis/users.acl ─────────────────────────────────────────────
  passwords::_write_acl \
    "${acl_file}" \
    "${pw_redis_admin}" \
    "${pw_redis_app}" \
    "${pw_redis_readonly}"

  print_ok "redis/users.acl updated"

  # ── Print summary ───────────────────────────────────────────────────────────
  passwords::_print_summary \
    "${pw_redis_admin}" \
    "${pw_redis_app}" \
    "${pw_redis_readonly}" \
    "${pw_rabbitmq}" \
    "${pw_grafana}"
}

# ── Helpers ────────────────────────────────────────────────────────────────────

# Set or replace a KEY=VALUE line in a .env file
# Usage: passwords::_set_env KEY VALUE /path/to/.env
passwords::_set_env() {
  local key="$1"
  local value="$2"
  local file="$3"

  if grep -q "^${key}=" "${file}" 2>/dev/null; then
    # Key exists — replace it (macOS and Linux compatible)
    if [ "${OS_TYPE}" = "macos" ]; then
      sed -i '' "s|^${key}=.*|${key}=${value}|" "${file}"
    else
      sed -i "s|^${key}=.*|${key}=${value}|" "${file}"
    fi
  else
    # Key doesn't exist — append it
    echo "${key}=${value}" >> "${file}"
  fi
}

# Rewrite redis/users.acl with fresh passwords
# ACL format: no comments allowed — Redis rejects any line not starting with "user"
passwords::_write_acl() {
  local file="$1"
  local pw_admin="$2"
  local pw_app="$3"
  local pw_readonly="$4"

  cat > "${file}" << EOF
user default off
user admin on >${pw_admin} ~* &* +@all
user appuser on >${pw_app} ~* &* +@read +@write +@string +@hash +@list +@set +@sortedset +@pubsub -@dangerous -@admin
user readonly on >${pw_readonly} ~* &* +@read -@dangerous
EOF
}

# Print a summary table of generated credentials
passwords::_print_summary() {
  local pw_redis_admin="$1"
  local pw_redis_app="$2"
  local pw_redis_readonly="$3"
  local pw_rabbitmq="$4"
  local pw_grafana="$5"

  echo ""
  echo "  ${_BOLD}Generated credentials${_RESET}"
  echo "  ${_CYAN}────────────────────────────────────────────────────────${_RESET}"
  printf "  %-28s %s\n" "Redis admin:"    "${pw_redis_admin}"
  printf "  %-28s %s\n" "Redis appuser:"  "${pw_redis_app}"
  printf "  %-28s %s\n" "Redis readonly:" "${pw_redis_readonly}"
  printf "  %-28s %s\n" "RabbitMQ admin:" "${pw_rabbitmq}"
  printf "  %-28s %s\n" "Grafana admin:"  "${pw_grafana}"
  echo "  ${_CYAN}────────────────────────────────────────────────────────${_RESET}"
  echo ""
  print_warn "Save these passwords. They are stored in .env and redis/users.acl."
  print_warn "Never commit .env to version control."
  echo ""
}
