#!/usr/bin/env bash
# setup.sh — redrab setup orchestrator (macOS + Linux)
#
# Usage:
#   ./setup.sh              — full setup (passwords, dashboards, start stack)
#   ./setup.sh --passwords  — regenerate passwords only (no stack restart)
#   ./setup.sh --dashboards — download/re-download Grafana dashboards only
#   ./setup.sh --validate   — run post-setup validation only
#   ./setup.sh --help       — show this help
#
# Requirements: Docker Desktop (macOS) or Docker Engine + Compose v2 (Linux)
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Resolve project root (directory containing this script) ───────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}" && pwd)"
export PROJECT_ROOT

# ── Load modules ──────────────────────────────────────────────────────────────
# shellcheck source=scripts/lib/colors.sh
source "${SCRIPT_DIR}/scripts/lib/colors.sh"
# shellcheck source=scripts/lib/os.sh
source "${SCRIPT_DIR}/scripts/lib/os.sh"
# shellcheck source=scripts/lib/passwords.sh
source "${SCRIPT_DIR}/scripts/lib/passwords.sh"
# shellcheck source=scripts/lib/dashboards.sh
source "${SCRIPT_DIR}/scripts/lib/dashboards.sh"
# shellcheck source=scripts/lib/validate.sh
source "${SCRIPT_DIR}/scripts/lib/validate.sh"

# ── Help ───────────────────────────────────────────────────────────────────────
usage() {
  cat <<EOF

${_BOLD}Usage:${_RESET}
  ./setup.sh              Full setup: passwords, dashboards, start stack, validate
  ./setup.sh --passwords  Regenerate passwords only (stack must be restarted manually)
  ./setup.sh --dashboards Download/re-download Grafana dashboards only
  ./setup.sh --validate   Run post-setup health validation only
  ./setup.sh --help       Show this help

EOF
  exit 0
}

# ── Modes ──────────────────────────────────────────────────────────────────────

mode::passwords_only() {
  print_header
  validate::preflight
  os::detect
  passwords::setup
  print_info "Passwords updated. Restart the stack to apply:"
  print_info "  docker compose -f docker-compose.yml -f docker-compose.monitoring.yml restart"
  echo ""
}

mode::dashboards_only() {
  print_header
  os::detect
  dashboards::setup
  echo ""
  print_ok "Done. Restart Grafana to reload dashboards:"
  print_info "  docker compose restart grafana"
  echo ""
}

mode::validate_only() {
  print_header
  os::detect
  validate::post_setup
  validate::print_access_summary
}

mode::full_setup() {
  print_header

  # 1. Pre-flight: abort early if requirements are not met
  validate::preflight

  # 2. Detect OS and apply system-level settings
  os::detect
  os::check_macos
  os::apply_linux_kernel_settings

  # 3. Generate passwords and inject into .env and users.acl
  passwords::setup

  # 4. Download and patch Grafana dashboards
  dashboards::setup

  # 5. Start the full stack
  print_section "Starting the stack"
  docker compose \
    -f "${PROJECT_ROOT}/docker-compose.yml" \
    -f "${PROJECT_ROOT}/docker-compose.monitoring.yml" \
    up -d

  print_ok "Stack started"

  # 6. Post-setup validation
  validate::post_setup
  validate::print_access_summary
}

# ── Entry point ────────────────────────────────────────────────────────────────
main() {
  local mode="${1:-full}"

  case "${mode}" in
    --help|-h)        usage ;;
    --passwords)      mode::passwords_only ;;
    --dashboards)     mode::dashboards_only ;;
    --validate)       mode::validate_only ;;
    full|"")          mode::full_setup ;;
    *)
      print_error "Unknown option: ${mode}"
      usage
      ;;
  esac
}

main "$@"
