#!/usr/bin/env bash
# scripts/lib/dashboards.sh
# Download and patch Grafana dashboards
# Sourced by setup.sh — do not execute directly

# Grafana dashboard IDs
readonly DASHBOARD_REDIS_ID=763
readonly DASHBOARD_RABBITMQ_ID=10991
readonly GRAFANA_DATASOURCE_UID="prometheus-ds"

dashboards::setup() {
  print_section "Downloading Grafana dashboards"

  local dashboards_dir="${PROJECT_ROOT}/grafana/provisioning/dashboards"

  if ! command -v curl &>/dev/null; then
    print_warn "curl not found — skipping dashboard download"
    print_info "Download manually:"
    print_info "  https://grafana.com/api/dashboards/${DASHBOARD_REDIS_ID}/revisions/latest/download"
    print_info "  https://grafana.com/api/dashboards/${DASHBOARD_RABBITMQ_ID}/revisions/latest/download"
    return 0
  fi

  dashboards::_download \
    "${DASHBOARD_REDIS_ID}" \
    "redis.json" \
    "${dashboards_dir}"

  dashboards::_download \
    "${DASHBOARD_RABBITMQ_ID}" \
    "rabbitmq-overview.json" \
    "${dashboards_dir}"
}

# ── Helpers ────────────────────────────────────────────────────────────────────

dashboards::_download() {
  local id="$1"
  local filename="$2"
  local dir="$3"
  local output="${dir}/${filename}"
  local url="https://grafana.com/api/dashboards/${id}/revisions/latest/download"

  print_info "Downloading dashboard #${id} → ${filename}"

  if curl -fsSL --connect-timeout 10 --max-time 30 -o "${output}" "${url}"; then
    dashboards::_patch "${output}"
    print_ok "Dashboard #${id} downloaded and patched"
  else
    print_warn "Failed to download dashboard #${id} (network issue?)"
    print_info "Download manually: ${url}"
    print_info "Then run: sed 's/\${DS_PROMETHEUS}/${GRAFANA_DATASOURCE_UID}/g' ${filename}"
  fi
}

# Replace the ${DS_PROMETHEUS} placeholder with the provisioned datasource UID
# sed syntax differs between macOS (requires empty string after -i) and Linux
dashboards::_patch() {
  local file="$1"

  if [ ! -f "${file}" ]; then
    return 1
  fi

  if [ "${OS_TYPE}" = "macos" ]; then
    sed -i '' "s/\${DS_PROMETHEUS}/${GRAFANA_DATASOURCE_UID}/g" "${file}"
  else
    sed -i "s/\${DS_PROMETHEUS}/${GRAFANA_DATASOURCE_UID}/g" "${file}"
  fi
}
