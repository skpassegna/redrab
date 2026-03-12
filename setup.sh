#!/usr/bin/env bash
# setup.sh — redrab configuration setup
#
# What this script does:
#   1. Checks if .env is present (creates it from .env.example if not)
#   2. Checks if passwords are still placeholders (CHANGE_ME)
#      YES → generates secure passwords and applies them to .env + redis/users.acl
#      NO  → verifies that redis/users.acl is in sync with .env
#   3. Downloads missing Grafana dashboards
#   4. Reports OS-specific kernel notes (informational only)
#
# What this script does NOT do:
#   - Start, stop, or restart containers
#   - Back up .env
#   - Require root / sudo
#
# Usage:
#   ./setup.sh              — full setup (passwords + dashboards + notes)
#   ./setup.sh --passwords  — passwords and config files only
#   ./setup.sh --dashboards — Grafana dashboards only
#   ./setup.sh --help
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}"
export PROJECT_ROOT OS_TYPE ARCH DOCKER_CONTEXT

source "${SCRIPT_DIR}/scripts/lib/colors.sh"
source "${SCRIPT_DIR}/scripts/lib/os.sh"
source "${SCRIPT_DIR}/scripts/lib/passwords.sh"
source "${SCRIPT_DIR}/scripts/lib/dashboards.sh"
source "${SCRIPT_DIR}/scripts/lib/validate.sh"

usage() {
  cat <<EOF

${_BOLD}Usage:${_RESET}
  ./setup.sh              Full setup: passwords + dashboards
  ./setup.sh --passwords  Passwords and config files only
  ./setup.sh --dashboards Grafana dashboards only
  ./setup.sh --help       Show this help

${_BOLD}To start the stack:${_RESET}
  docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d

${_BOLD}To check the running stack:${_RESET}
  ./validate.sh

EOF
  exit 0
}

main() {
  local mode="${1:-full}"

  case "${mode}" in
    --help|-h)
      usage
      ;;
    --passwords)
      print_header "Setup — Passwords"
      validate::preflight
      os::detect
      passwords::setup
      echo ""
      print_info "Next: start or restart the stack to apply changes"
      print_info "  docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d"
      echo ""
      ;;
    --dashboards)
      print_header "Setup — Dashboards"
      os::detect
      dashboards::setup
      echo ""
      print_info "If Grafana is running, restart it to reload:"
      print_info "  docker compose restart grafana"
      echo ""
      ;;
    full|"")
      print_header "Setup"
      validate::preflight
      os::detect
      os::print_kernel_notes
      passwords::setup
      dashboards::setup
      echo ""
      print_ok "Setup complete"
      print_info "Start the stack with:"
      print_info "  docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d"
      print_info "Then check the stack:"
      print_info "  ./validate.sh"
      echo ""
      ;;
    *)
      print_error "Unknown option: ${mode}"
      usage
      ;;
  esac
}

main "$@"
