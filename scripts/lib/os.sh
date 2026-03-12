#!/usr/bin/env bash
# scripts/lib/os.sh
# OS detection and system-level configuration checks
# Sourced by other scripts — do not execute directly

# Sets globals: OS_TYPE (macos | linux | unknown), ARCH, DOCKER_CONTEXT
os::detect() {
  print_section "Detecting environment"

  case "$(uname -s)" in
    Darwin) OS_TYPE="macos"  ; print_ok "OS: macOS" ;;
    Linux)  OS_TYPE="linux"  ; print_ok "OS: Linux" ;;
    *)      OS_TYPE="unknown"; print_warn "Unknown OS — some checks skipped" ;;
  esac

  case "$(uname -m)" in
    x86_64)        ARCH="x86_64" ;;
    arm64|aarch64) ARCH="arm64"  ;;
    *)             ARCH="unknown" ;;
  esac
  print_ok "Architecture: ${ARCH}"

  if docker info 2>/dev/null | grep -q "Operating System: Docker Desktop"; then
    DOCKER_CONTEXT="docker-desktop"
    print_ok "Docker context: Docker Desktop"
  else
    DOCKER_CONTEXT="native"
    print_ok "Docker context: native"
  fi
}

# Print OS-specific notes about kernel settings
# This is informational only — setup.sh never modifies kernel settings
os::print_kernel_notes() {
  print_section "Kernel settings (Redis)"

  case "${OS_TYPE}" in
    macos)
      print_ok "macOS / Docker Desktop: kernel settings managed internally — nothing to do"
      print_info "Redis warnings about vm.overcommit_memory in logs are cosmetic — safe to ignore"
      ;;
    linux)
      local overcommit
      overcommit=$(cat /proc/sys/vm/overcommit_memory 2>/dev/null || echo "unknown")

      if [ "${overcommit}" = "1" ]; then
        print_ok "vm.overcommit_memory = 1 (already set)"
      else
        print_warn "vm.overcommit_memory = ${overcommit} (recommended: 1)"
        print_info "To fix (one-time, requires sudo):"
        print_info "  echo 'vm.overcommit_memory = 1' | sudo tee /etc/sysctl.d/99-redis.conf"
        print_info "  sudo sysctl -p /etc/sysctl.d/99-redis.conf"
      fi

      local thp_path="/sys/kernel/mm/transparent_hugepage/enabled"
      if [ -f "${thp_path}" ]; then
        if grep -q "\[never\]" "${thp_path}"; then
          print_ok "Transparent Huge Pages: disabled (correct)"
        else
          print_warn "Transparent Huge Pages: not disabled"
          print_info "To fix:"
          print_info "  echo never | sudo tee ${thp_path}"
        fi
      fi
      ;;
    *)
      print_info "Kernel checks not applicable on this OS"
      ;;
  esac
}
