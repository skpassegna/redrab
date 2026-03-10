#!/usr/bin/env bash
# scripts/lib/os.sh
# OS detection and system-level configuration
# Sourced by setup.sh — do not execute directly

# ── OS Detection ───────────────────────────────────────────────────────────────

# Sets: OS_TYPE (macos | linux | unknown), ARCH (x86_64 | arm64 | unknown)
os::detect() {
  print_section "Detecting environment"

  case "$(uname -s)" in
    Darwin)
      OS_TYPE="macos"
      print_ok "Operating system: macOS"
      ;;
    Linux)
      OS_TYPE="linux"
      # Detect if running inside Docker Desktop's LinuxKit VM
      if grep -qi "linuxkit" /proc/version 2>/dev/null; then
        OS_TYPE="linuxkit"
        print_ok "Operating system: Linux (Docker Desktop LinuxKit VM)"
      else
        print_ok "Operating system: Linux"
      fi
      ;;
    *)
      OS_TYPE="unknown"
      print_warn "Unknown OS — skipping system-level checks"
      ;;
  esac

  case "$(uname -m)" in
    x86_64)  ARCH="x86_64"  ;;
    arm64)   ARCH="arm64"   ;;
    aarch64) ARCH="arm64"   ;;
    *)       ARCH="unknown" ;;
  esac
  print_ok "Architecture: ${ARCH}"

  # Docker context
  if docker info 2>/dev/null | grep -q "Operating System: Docker Desktop"; then
    DOCKER_CONTEXT="docker-desktop"
    print_ok "Docker context: Docker Desktop"
  else
    DOCKER_CONTEXT="native"
    print_ok "Docker context: native"
  fi
}

# ── Linux: kernel parameters ───────────────────────────────────────────────────

# Apply vm.overcommit_memory and disable Transparent Huge Pages
# Required for Redis AOF/RDB background saves on native Linux
os::apply_linux_kernel_settings() {
  if [ "${OS_TYPE}" != "linux" ]; then
    return 0
  fi

  print_section "Linux kernel settings (Redis requirements)"

  # ── vm.overcommit_memory ────────────────────────────────────────────────────
  local current_overcommit
  current_overcommit=$(cat /proc/sys/vm/overcommit_memory 2>/dev/null || echo "unknown")

  if [ "${current_overcommit}" = "1" ]; then
    print_ok "vm.overcommit_memory is already set to 1"
  else
    print_info "Setting vm.overcommit_memory = 1 (current: ${current_overcommit})"
    if [ "$(id -u)" -eq 0 ]; then
      echo "vm.overcommit_memory = 1" > /etc/sysctl.d/99-redis.conf
      sysctl -p /etc/sysctl.d/99-redis.conf >/dev/null 2>&1
      print_ok "vm.overcommit_memory set to 1 (persists across reboots)"
    else
      print_warn "Not running as root — applying temporarily (won't persist)"
      sudo sysctl -w vm.overcommit_memory=1 2>/dev/null || \
        print_warn "sudo failed — set manually: sudo sysctl -w vm.overcommit_memory=1"

      print_info "To make it persistent, run:"
      print_info "  echo 'vm.overcommit_memory = 1' | sudo tee /etc/sysctl.d/99-redis.conf"
      print_info "  sudo sysctl -p /etc/sysctl.d/99-redis.conf"
    fi
  fi

  # ── Transparent Huge Pages ──────────────────────────────────────────────────
  local thp_path="/sys/kernel/mm/transparent_hugepage/enabled"
  if [ -f "${thp_path}" ]; then
    local current_thp
    current_thp=$(cat "${thp_path}" 2>/dev/null)
    if echo "${current_thp}" | grep -q "\[never\]"; then
      print_ok "Transparent Huge Pages already disabled"
    else
      print_info "Disabling Transparent Huge Pages (current: ${current_thp})"
      if echo never | sudo tee "${thp_path}" >/dev/null 2>&1; then
        print_ok "Transparent Huge Pages disabled"
        print_warn "This setting resets on reboot — add to /etc/rc.local for persistence"
      else
        print_warn "Could not disable THP — set manually: echo never | sudo tee ${thp_path}"
      fi
    fi
  else
    print_info "Transparent Huge Pages path not found — skipping"
  fi
}

# ── macOS / Docker Desktop ─────────────────────────────────────────────────────

os::check_macos() {
  if [ "${OS_TYPE}" != "macos" ]; then
    return 0
  fi

  print_section "macOS / Docker Desktop checks"

  # Verify Docker Desktop is running
  if ! docker info &>/dev/null; then
    print_fatal "Docker Desktop does not appear to be running. Start it and retry."
  fi
  print_ok "Docker Desktop is running"

  # vm.overcommit_memory and THP are handled by Docker Desktop's LinuxKit VM
  print_ok "vm.overcommit_memory — managed by Docker Desktop (no action needed)"
  print_ok "Transparent Huge Pages — managed by Docker Desktop (no action needed)"
  print_info "Redis kernel warnings in logs are cosmetic on macOS — safe to ignore"
}
