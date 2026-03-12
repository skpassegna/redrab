# Changelog

All notable changes to this project are documented here.


## [1.2.0] — 2026-03-12

### Added

- `setup.sh` — configuration setup script for macOS and Linux:
  - Checks if `.env` is present; creates it from `.env.example` if not
  - Detects placeholder passwords (`CHANGE_ME`) in `.env` — generates new secure
    passwords if found, verifies file sync if not
  - Generates alphanumeric 32-character passwords via `/dev/urandom` (no special
    characters — avoids parsing issues in `.env`, Redis ACL, and AMQP URIs)
  - Applies passwords to `.env` and rewrites `redis/users.acl` atomically
  - Downloads missing Grafana dashboards and patches the `${DS_PROMETHEUS}` placeholder
  - Reports OS-specific kernel notes (informational only — never modifies kernel settings)
  - Never starts, stops, or restarts containers
  - Never creates `.env` backups
  - Modes: `full` (default) · `--passwords` · `--dashboards` · `--help`
- `setup.ps1` — equivalent setup script for Windows (PowerShell 5.1+):
  - Same logic as `setup.sh` — placeholder detection, password generation, file sync
  - Uses `RNGCryptoServiceProvider` for cryptographically secure password generation
  - Writes `redis/users.acl` with Unix LF line endings (required by Redis)
  - Writes all files as UTF-8 without BOM
  - Modes: `full` (default) · `passwords` · `dashboards` · `--help`
- `setup.bat` — Windows entry point; detects `pwsh` or `powershell`, invokes `setup.ps1`
- `validate.sh` — read-only stack validation for macOS and Linux:
  - `--config`: checks `.env` for placeholders, `users.acl` sync, dashboard presence
    (no running stack required)
  - `--runtime`: checks container status, probes Redis / RabbitMQ / Prometheus /
    redis_exporter health, prints web interface URLs
  - Never modifies any file or touches any container
- `validate.ps1` — equivalent validation script for Windows (PowerShell 5.1+)
- `validate.bat` — Windows entry point for `validate.ps1`
- `scripts/lib/colors.sh` — terminal color helpers sourced by shell scripts
- `scripts/lib/os.sh` — OS and architecture detection, Docker context, kernel notes
- `scripts/lib/passwords.sh` — password generation, `.env` injection, ACL rewrite
- `scripts/lib/dashboards.sh` — Grafana dashboard download and datasource patch
- `scripts/lib/validate.sh` — pre-flight checks, config validation, runtime health probes
- `CONTRIBUTING.md` — contribution guide: bug reports, feature requests, PR process,
  style guidelines for configs, ACL files, docs, and commit messages
- `SECURITY.md` — vulnerability reporting process, security defaults documented
  (Redis default user disabled, ports on 127.0.0.1, no hardcoded secrets),
  known limitations (plaintext `.env`, no TLS by default)
- `CHANGELOG.md` — this file
- `.github/ISSUE_TEMPLATE/bug_report.yml` — structured bug report form with service
  dropdown, log field, environment info, and steps to reproduce
- `.github/ISSUE_TEMPLATE/feature_request.yml` — structured feature request form
- `.github/PULL_REQUEST_TEMPLATE.md` — PR checklist with stack start, health check,
  log verification, dual README sync, and security review items

### Changed

- `.gitignore` — translated to English; added `.env.backup.*` to prevent accidental
  commit of backup files


## [1.1.0] — 2026-03-10

### Fixed

- **Redis ACL** — removed comments (`#`) from `redis/users.acl`; Redis rejects any line
  that does not start with the `user` keyword, causing an immediate startup crash
- **Redis healthcheck** — replaced `redis-cli -a $REDIS_PASSWORD ping | grep PONG` with
  `redis-cli ping 2>&1 | grep -qE 'PONG|NOAUTH'`; the previous command failed because
  `user default off` in the ACL blocks connections that don't specify an explicit username,
  and the `$REDIS_PASSWORD` variable is not available inside the container exec context
- **Redis healthcheck timing** — increased `start_period` from `10s` to `30s` to account
  for AOF file loading time on restart
- **RabbitMQ deprecated env var** — removed `RABBITMQ_VM_MEMORY_HIGH_WATERMARK` from
  `docker-compose.yml`; this variable is deprecated in RabbitMQ 4.x and caused a crash
  loop on startup. The setting is already correctly defined in `rabbitmq/rabbitmq.conf`
  via `vm_memory_high_watermark.relative`
- **Monitoring network** — removed `external: true` from the `infra-backend` network
  declaration in `docker-compose.monitoring.yml`; when both Compose files are merged
  with `-f`, Docker creates the network automatically and `external: true` caused a
  "network could not be found" error on first run

### Added

- `.gitignore` with entries for `.env`, certificates, local backups, dashboard JSON files,
  and common editor/OS artifacts
- macOS-specific documentation in `README.md` and `README.fr.md` clarifying that
  `vm.overcommit_memory` and Transparent Huge Pages settings are not needed on
  Docker Desktop (handled by the internal LinuxKit VM)
- Troubleshooting entry for the `network infra-backend could not be found` error


## [1.0.0] — 2026-03-10

### Added

- `docker-compose.yml` — production Redis 7 + RabbitMQ 4 stack with healthchecks,
  resource limits, fixed hostname for RabbitMQ, and named volumes
- `docker-compose.monitoring.yml` — full monitoring stack:
  - **RedisInsight** (official Redis GUI, port 5540)
  - **redis_exporter** by oliver006 (Prometheus exporter, port 9121)
  - **RabbitMQ Management UI** (native, port 15672)
  - **RabbitMQ Prometheus plugin** (native, port 15692)
  - **RabbitScout** (modern open source RabbitMQ GUI, port 3001)
  - **Prometheus** (metrics collection, port 9090)
  - **Grafana** (dashboards, port 3002)
- `redis/redis.conf` — production Redis config: AOF + RDB hybrid persistence,
  ACL file, maxmemory with LRU eviction, lazyfree, slowlog, tcp-keepalive
- `redis/users.acl` — three ACL users: `admin` (full), `appuser` (read/write),
  `readonly` (read only); `default` user disabled
- `rabbitmq/rabbitmq.conf` — production RabbitMQ config: memory watermark, disk
  limit, heartbeat, Prometheus port, TLS section (commented)
- `rabbitmq/enabled_plugins` — `rabbitmq_management` and `rabbitmq_prometheus`
- `prometheus/prometheus.yml` — scrape configs for Redis exporter and RabbitMQ
- `grafana/provisioning/datasources/datasources.yml` — Prometheus auto-connected
- `grafana/provisioning/dashboards/dashboards.yml` — dashboard file provider
- `.env.example` — all required environment variables with safe placeholder values
- `README.md` — full English documentation
- `README.fr.md` — full French documentation
