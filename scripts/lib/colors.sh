#!/usr/bin/env bash
# scripts/lib/colors.sh
# Terminal colors and print helpers
# Sourced by setup.sh — do not execute directly

# Detect if terminal supports colors
if [ -t 1 ] && command -v tput &>/dev/null && tput colors &>/dev/null; then
  _BOLD=$(tput bold)
  _RESET=$(tput sgr0)
  _RED=$(tput setaf 1)
  _GREEN=$(tput setaf 2)
  _YELLOW=$(tput setaf 3)
  _BLUE=$(tput setaf 4)
  _CYAN=$(tput setaf 6)
else
  _BOLD="" _RESET="" _RED="" _GREEN="" _YELLOW="" _BLUE="" _CYAN=""
fi

# ── Print helpers ──────────────────────────────────────────────────────────────

print_header() {
  echo ""
  echo "${_BOLD}${_BLUE}══════════════════════════════════════════════════════${_RESET}"
  echo "${_BOLD}${_BLUE}  🐳 redrab — Setup Script${_RESET}"
  echo "${_BOLD}${_BLUE}     Redis + RabbitMQ Production Stack${_RESET}"
  echo "${_BOLD}${_BLUE}══════════════════════════════════════════════════════${_RESET}"
  echo ""
}

print_section() {
  echo ""
  echo "${_BOLD}${_CYAN}▶ $1${_RESET}"
}

print_ok() {
  echo "  ${_GREEN}✔${_RESET}  $1"
}

print_warn() {
  echo "  ${_YELLOW}⚠${_RESET}  $1"
}

print_error() {
  echo "  ${_RED}✘${_RESET}  $1" >&2
}

print_info() {
  echo "  ${_BLUE}•${_RESET}  $1"
}

print_fatal() {
  echo ""
  echo "${_RED}${_BOLD}FATAL: $1${_RESET}" >&2
  echo ""
  exit 1
}
