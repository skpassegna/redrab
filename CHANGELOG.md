# Changelog

All notable changes to this project are documented here.

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
