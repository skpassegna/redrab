#!/usr/bin/env bash
# scripts/lib/passwords.sh
# Password logic: detect state, generate, and apply to config files
# Sourced by setup.sh — do not execute directly
#
# Password policy: alphanumeric [A-Za-z0-9], 32 chars
# No special characters — avoids parsing issues in .env files,
# Redis ACL inline format, and AMQP URI percent-encoding.

readonly PLACEHOLDER_PATTERN="CHANGE_ME"

# ── Main entry point ───────────────────────────────────────────────────────────
# Decides whether to generate new passwords or verify existing ones

passwords::setup() {
  print_section "Secrets configuration"

  local env_file="${PROJECT_ROOT}/.env"
  local env_example="${PROJECT_ROOT}/.env.example"

  # ── Step 1: ensure .env exists ─────────────────────────────────────────────
  if [ ! -f "${env_file}" ]; then
    if [ ! -f "${env_example}" ]; then
      print_fatal ".env.example not found — cannot continue"
    fi
    cp "${env_example}" "${env_file}"
    print_ok ".env created from .env.example"
    # Fresh copy always has CHANGE_ME placeholders → fall through to generate
  else
    print_ok ".env found"
  fi

  # ── Step 2: check if placeholders are still present ────────────────────────
  if passwords::_has_placeholders "${env_file}"; then
    print_warn "Placeholder passwords detected in .env — generating new passwords"
    passwords::_generate_and_apply "${env_file}"
  else
    print_ok "Passwords already set in .env"
    passwords::_verify_sync "${env_file}"
  fi
}

# ── Check for CHANGE_ME placeholders in password fields ───────────────────────

passwords::_has_placeholders() {
  local file="$1"
  grep -qE "^(REDIS_PASSWORD|REDIS_EXPORTER_PASSWORD|RABBITMQ_PASSWORD|GF_ADMIN_PASSWORD)=.*${PLACEHOLDER_PATTERN}" "${file}"
}

# ── Generate new passwords and apply to all config files ──────────────────────

passwords::_generate_and_apply() {
  local env_file="$1"

  local pw_redis_admin    ; pw_redis_admin=$(passwords::_generate)
  local pw_redis_app      ; pw_redis_app=$(passwords::_generate)
  local pw_redis_readonly ; pw_redis_readonly=$(passwords::_generate)
  local pw_rabbitmq       ; pw_rabbitmq=$(passwords::_generate)
  local pw_grafana        ; pw_grafana=$(passwords::_generate)

  print_ok "Passwords generated (32-char alphanumeric)"

  # Apply to .env
  passwords::_set_env "REDIS_PASSWORD"           "${pw_redis_admin}"  "${env_file}"
  passwords::_set_env "REDIS_EXPORTER_PASSWORD"  "${pw_redis_app}"    "${env_file}"
  passwords::_set_env "RABBITMQ_PASSWORD"        "${pw_rabbitmq}"     "${env_file}"
  passwords::_set_env "GF_ADMIN_PASSWORD"        "${pw_grafana}"      "${env_file}"
  print_ok ".env updated"

  # Apply to redis/users.acl
  passwords::_write_acl \
    "${PROJECT_ROOT}/redis/users.acl" \
    "${pw_redis_admin}" \
    "${pw_redis_app}" \
    "${pw_redis_readonly}"
  print_ok "redis/users.acl updated"

  passwords::_print_summary \
    "${pw_redis_admin}" "${pw_redis_app}" "${pw_redis_readonly}" \
    "${pw_rabbitmq}" "${pw_grafana}"
}

# ── Verify that users.acl is in sync with .env ────────────────────────────────
# If the ACL still contains CHANGE_ME but .env has real passwords,
# the ACL is rewritten to match .env.

passwords::_verify_sync() {
  local env_file="$1"
  local acl_file="${PROJECT_ROOT}/redis/users.acl"

  print_section "Verifying file sync"

  if [ ! -f "${acl_file}" ]; then
    print_error "redis/users.acl not found"
    return 1
  fi

  # Read current passwords from .env
  local pw_admin pw_app pw_exporter
  pw_admin=$(passwords::_read_env "REDIS_PASSWORD"          "${env_file}")
  pw_app=$(passwords::_read_env   "REDIS_EXPORTER_PASSWORD" "${env_file}")

  # Check if ACL still has placeholders
  if grep -q "${PLACEHOLDER_PATTERN}" "${acl_file}"; then
    print_warn "redis/users.acl has placeholder passwords — syncing with .env"

    local pw_readonly
    pw_readonly=$(passwords::_generate)  # generate a readonly pw (not in .env)

    passwords::_write_acl "${acl_file}" "${pw_admin}" "${pw_app}" "${pw_readonly}"
    print_ok "redis/users.acl synced with .env"
    print_warn "A new readonly password was generated (not stored in .env — for internal use only)"
  else
    # Verify appuser password in ACL matches REDIS_EXPORTER_PASSWORD
    if grep -q "user appuser on >${pw_exporter} " "${acl_file}" 2>/dev/null || \
       grep -q "user appuser on >${pw_app} "      "${acl_file}" 2>/dev/null; then
      print_ok "redis/users.acl is in sync with .env"
    else
      print_warn "redis/users.acl appuser password may differ from REDIS_EXPORTER_PASSWORD"
      print_info "If redis_exporter shows WRONGPASS, re-run: ./setup.sh"
    fi

    if grep -q "user admin on >${pw_admin} " "${acl_file}" 2>/dev/null; then
      print_ok "redis/users.acl admin password matches REDIS_PASSWORD"
    else
      print_warn "redis/users.acl admin password may differ from REDIS_PASSWORD in .env"
      print_info "Re-run ./setup.sh to regenerate and sync all passwords"
    fi
  fi
}

# ── Helpers ────────────────────────────────────────────────────────────────────

passwords::_generate() {
  LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32
}

# Read the value of a KEY from a .env file
passwords::_read_env() {
  local key="$1"
  local file="$2"
  grep "^${key}=" "${file}" | cut -d'=' -f2-
}

# Set or replace a KEY=VALUE line in a .env file (macOS + Linux compatible)
passwords::_set_env() {
  local key="$1"
  local value="$2"
  local file="$3"

  if grep -q "^${key}=" "${file}"; then
    if [ "${OS_TYPE}" = "macos" ]; then
      sed -i '' "s|^${key}=.*|${key}=${value}|" "${file}"
    else
      sed -i "s|^${key}=.*|${key}=${value}|" "${file}"
    fi
  else
    echo "${key}=${value}" >> "${file}"
  fi
}

# Rewrite redis/users.acl — no comments (Redis rejects them)
passwords::_write_acl() {
  local file="$1"
  local pw_admin="$2"
  local pw_app="$3"
  local pw_readonly="$4"

  cat > "${file}" <<EOF
user default off
user admin on >${pw_admin} ~* &* +@all
user appuser on >${pw_app} ~* &* +@read +@write +@string +@hash +@list +@set +@sortedset +@pubsub -@dangerous -@admin
user readonly on >${pw_readonly} ~* &* +@read -@dangerous
EOF
}

passwords::_print_summary() {
  local pw_redis_admin="$1"
  local pw_redis_app="$2"
  local pw_redis_readonly="$3"
  local pw_rabbitmq="$4"
  local pw_grafana="$5"

  echo ""
  echo "  ${_BOLD}Generated credentials${_RESET}"
  echo "  ${_CYAN}──────────────────────────────────────────────────${_RESET}"
  printf "  %-28s %s\n" "Redis admin:"    "${pw_redis_admin}"
  printf "  %-28s %s\n" "Redis appuser:"  "${pw_redis_app}"
  printf "  %-28s %s\n" "Redis readonly:" "${pw_redis_readonly}"
  printf "  %-28s %s\n" "RabbitMQ admin:" "${pw_rabbitmq}"
  printf "  %-28s %s\n" "Grafana admin:"  "${pw_grafana}"
  echo "  ${_CYAN}──────────────────────────────────────────────────${_RESET}"
  echo ""
  print_warn "These are the only time these passwords are displayed."
  print_warn "They are stored in .env and redis/users.acl — never commit .env."
  echo ""
}
