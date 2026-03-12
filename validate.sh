#!/usr/bin/env bash
# validate.sh — redrab stack validation
#
# What this script does:
#   1. Checks configuration files (.env, users.acl, dashboards)
#   2. Checks running container status
#   3. Probes service health (Redis, RabbitMQ, Prometheus, redis_exporter)
#
# What this script does NOT do:
#   - Modify any file
#   - Start, stop, or restart any container
#   - Generate passwords
#
# Usage:
#   ./validate.sh           — config check + runtime check
#   ./validate.sh --config  — config files only (no running stack required)
#   ./validate.sh --runtime — running services only
#   ./validate.sh --help
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}"
export PROJECT_ROOT OS_TYPE ARCH DOCKER_CONTEXT

source "${SCRIPT_DIR}/scripts/lib/colors.sh"
source "${SCRIPT_DIR}/scripts/lib/os.sh"
source "${SCRIPT_DIR}/scripts/lib/validate.sh"

usage() {
  cat <<EOF

${_BOLD}Usage:${_RESET}
  ./validate.sh           Config check + runtime service health
  ./validate.sh --config  Config files only (stack doesn't need to be running)
  ./validate.sh --runtime Running services only
  ./validate.sh --help    Show this help

EOF
  exit 0
}

main() {
  local mode="${1:-full}"

  case "${mode}" in
    --help|-h)
      usage
      ;;
    --config)
      print_header "Validate — Config"
      os::detect
      validate::config
      echo ""
      ;;
    --runtime)
      print_header "Validate — Runtime"
      os::detect
      validate::runtime
      ;;
    full|"")
      print_header "Validate"
      os::detect
      validate::config
      validate::runtime
      ;;
    *)
      print_error "Unknown option: ${mode}"
      usage
      ;;
  esac
}

main "$@"
