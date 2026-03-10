# :whale: Redis + RabbitMQ — Production Infrastructure & Monitoring Stack

> Production-ready Docker Compose setup · Built **2026-03-10**

## Table of Contents

1. [Overview](#overview)
2. [Project Structure](#-project-structure)
3. [Quick Start](#-quick-start)
4. [Ports & URLs](#-ports--urls)
5. [Connection URIs](#-connection-uris)
   - [Redis](#redis)
   - [RabbitMQ](#rabbitmq)
6. [Web Interfaces — Usage Guides](#-web-interfaces--usage-guides)
   - [RabbitMQ Management UI](#1--rabbitmq-management-ui--localhost15672)
   - [RedisInsight](#2--redisinsight--localhost5540)
   - [RabbitScout](#3--rabbitscout--localhost3001)
   - [Prometheus](#4--prometheus--localhost9090)
   - [Grafana](#5--grafana--localhost3002)
7. [Service Configuration](#-service-configuration)
8. [Useful Commands](#-useful-commands)
9. [Production Checklist](#-production-checklist)
10. [Troubleshooting](#-troubleshooting)

---

## Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                           YOUR PROJECTS                             │
│   redis://appuser:***@localhost:6379   amqp://admin:***@localhost:5672│
└──────────────────┬──────────────────────────────┬───────────────────┘
                   │                              │
         ┌─────────▼──────────┐       ┌───────────▼──────────┐
         │      REDIS :6379   │       │   RABBITMQ :5672     │
         │    (redis:7-alpine)│       │  (rabbitmq:4-mgmt)   │
         └─────────┬──────────┘       └───────────┬──────────┘
                   │                              │
         ┌─────────▼──────────┐       ┌───────────▼──────────┐
         │  redis_exporter    │       │  rabbitmq_prometheus  │
         │     :9121          │       │       :15692          │
         └─────────┬──────────┘       └───────────┬──────────┘
                   │                              │
                   └──────────────┬───────────────┘
                                  │
                        ┌─────────▼──────────┐
                        │    PROMETHEUS       │
                        │      :9090          │
                        └─────────┬──────────┘
                                  │
                        ┌─────────▼──────────┐
                        │      GRAFANA        │
                        │      :3002          │
                        └─────────────────────┘

Direct web interfaces:
  RedisInsight  :5540   ← Official Redis GUI
  RabbitMQ UI  :15672   ← Native Management UI
  RabbitScout  :3001    ← Modern RabbitMQ GUI
```


## Project Structure

```
redrab/
├── docker-compose.yml                        ← Infra: Redis + RabbitMQ
├── docker-compose.monitoring.yml             ← Monitoring: Prometheus, Grafana, UIs
├── .env.example                              ← Variables template (cp → .env)
├── .env                                      ← Real secrets (⚠ never commit)
│
├── redis/
│   ├── redis.conf                            ← Redis 7.x production config
│   │                                             AOF + RDB + ACL + tuning
│   └── users.acl                             ← ACL users
│                                                 (admin, appuser, readonly)
│
├── rabbitmq/
│   ├── rabbitmq.conf                         ← RabbitMQ 4.x production config
│   │                                             memory, disk, heartbeat, Prometheus
│   └── enabled_plugins                       ← management + prometheus enabled
│
├── prometheus/
│   └── prometheus.yml                        ← Scrapes Redis :9121 + RabbitMQ :15692
│
└── grafana/
    └── provisioning/
        ├── datasources/
        │   └── datasources.yml               ← Prometheus auto-connected
        └── dashboards/
            ├── dashboards.yml                ← Dashboard auto-loader
            ├── redis.json                    ← ⬇ To download (Dashboard #763)
            └── rabbitmq-overview.json        ← ⬇ To download (Dashboard #10991)
```


## Quick Start

### Step 1 — System Requirements

#### macOS (Docker Desktop) — Nothing to do

Docker Desktop ships with an internal Linux VM (LinuxKit) that already handles
`vm.overcommit_memory` and Transparent Huge Pages. **Jump directly to Step 2.**

Redis may show cosmetic kernel warnings in its logs — this is expected and harmless
on Docker Desktop macOS.

```bash
# Just verify Docker Desktop is running
docker info | grep "Operating System"
# → Operating System: Docker Desktop
```

#### Linux — Production server / VPS (ONE TIME ONLY)

```bash
# Overcommit memory — required for background AOF/RDB saves
echo "vm.overcommit_memory = 1" | sudo tee /etc/sysctl.d/99-redis.conf
sudo sysctl -p /etc/sysctl.d/99-redis.conf

# Disable Transparent Huge Pages (reduces Redis latency)
echo never | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
```

### Step 2 — Configure secrets

```bash
cp .env.example .env
nano .env
```

You **must** fill in:
- `REDIS_PASSWORD`
- `REDIS_EXPORTER_PASSWORD` (must match the `appuser` password in `redis/users.acl`)
- `RABBITMQ_PASSWORD`
- `GF_ADMIN_PASSWORD`

Then update passwords in `redis/users.acl`:
```bash
nano redis/users.acl
# Replace CHANGE_ME_ADMIN_PASSWORD, CHANGE_ME_APP_PASSWORD, CHANGE_ME_READONLY_PASSWORD
```

### Step 3 — Download Grafana dashboards

```bash
# Redis dashboard (ID 763)
curl -o grafana/provisioning/dashboards/redis.json \
  "https://grafana.com/api/dashboards/763/revisions/latest/download"

# RabbitMQ Overview dashboard (ID 10991 — official RabbitMQ team)
curl -o grafana/provisioning/dashboards/rabbitmq-overview.json \
  "https://grafana.com/api/dashboards/10991/revisions/latest/download"

# Fix the datasource placeholder in the downloaded JSON files
# macOS:
sed -i '' 's/\${DS_PROMETHEUS}/prometheus-ds/g' grafana/provisioning/dashboards/*.json
# Linux:
sed -i 's/\${DS_PROMETHEUS}/prometheus-ds/g' grafana/provisioning/dashboards/*.json
```

### Step 4 — Start

```bash
# Start everything (recommended)
docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d

# Check all services are UP
docker compose -f docker-compose.yml -f docker-compose.monitoring.yml ps
```


##  Ports & URLs

| Service              | Host port | URL                            | Notes                               |
|----------------------|-----------|--------------------------------|-------------------------------------|
| Redis RESP           | `6379`    | —                              | Direct application connection       |
| RabbitMQ AMQP        | `5672`    | —                              | Direct application connection       |
| **RabbitMQ UI**      | `15672`   | http://localhost:15672         | Native RabbitMQ Management UI       |
| RabbitMQ Prometheus  | `15692`   | http://localhost:15692/metrics | Raw metrics (Prometheus scrape)     |
| redis_exporter       | `9121`    | http://localhost:9121/metrics  | Raw Redis metrics                   |
| **RedisInsight**     | `5540`    | http://localhost:5540          | Official Redis GUI                  |
| **RabbitScout**      | `3001`    | http://localhost:3001          | Modern open source RabbitMQ GUI     |
| **Prometheus**       | `9090`    | http://localhost:9090          | PromQL query interface              |
| **Grafana**          | `3002`    | http://localhost:3002          | Dashboards                          |

> All ports are bound to `127.0.0.1` by default — local access only.
> To expose remotely, use a reverse proxy (Nginx, Caddy) with TLS.

## Connection URIs

> The examples below use the values from `.env.example`.
> Replace the passwords with your actual values.

### Redis

#### Standard URI format

```
redis://<user>:<password>@<host>:<port>/<db>
```

#### URIs by context

```bash
# ── From a project OUTSIDE Docker (local process, scripts, etc.) ────────
redis://appuser:CHANGE_ME_APP_PASSWORD@localhost:6379/0

# ── From a container on the SAME Docker network (infra-backend) ─────────
redis://appuser:CHANGE_ME_APP_PASSWORD@redis:6379/0

# ── Admin user (maintenance, migrations) ────────────────────────────────
redis://admin:CHANGE_ME_ADMIN_PASSWORD@localhost:6379/0

# ── Readonly user (analytics, read-only access) ─────────────────────────
redis://readonly:CHANGE_ME_READONLY_PASSWORD@localhost:6379/0
```

#### Environment variables for your project

```bash
REDIS_URL=redis://appuser:CHANGE_ME_APP_PASSWORD@localhost:6379/0
# or split form:
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_USER=appuser
REDIS_PASSWORD=CHANGE_ME_APP_PASSWORD
REDIS_DB=0
```


### RabbitMQ

#### Standard URI format (AMQP)

```
amqp://<user>:<password>@<host>:<port>/<vhost>
amqps://<user>:<password>@<host>:<port>/<vhost>   ← with TLS
```

> The root vhost `/` must be URL-encoded as `%2F` in the URI.

#### URIs by context

```bash
# ── From a project OUTSIDE Docker (local process, scripts, etc.) ────────
amqp://admin:CHANGE_ME_RABBIT_PASSWORD@localhost:5672/%2F

# ── From a container on the SAME Docker network (infra-backend) ─────────
amqp://admin:CHANGE_ME_RABBIT_PASSWORD@rabbitmq:5672/%2F

# ── With a custom vhost ──────────────────────────────────────────────────
amqp://admin:CHANGE_ME_RABBIT_PASSWORD@localhost:5672/my_vhost
```

#### Environment variables for your project

```bash
RABBITMQ_URL=amqp://admin:CHANGE_ME_RABBIT_PASSWORD@localhost:5672
RABBITMQ_HOST=localhost
RABBITMQ_PORT=5672
RABBITMQ_USER=admin
RABBITMQ_PASSWORD=CHANGE_ME_RABBIT_PASSWORD
RABBITMQ_VHOST=/
```


## Web Interfaces — Usage Guides


### 1. RabbitMQ Management UI — `localhost:15672`

**The official native RabbitMQ web interface, included with no extra configuration.**

#### Login
1. Open http://localhost:15672
2. Username: `admin` / Password: your `RABBITMQ_PASSWORD` from `.env`

#### Navigation

| Tab          | What you do there                                                   |
|--------------|---------------------------------------------------------------------|
| **Overview** | Global view: messages/s, connections, channels, memory, disk       |
| **Connections** | All open connections (IP, user, vhost, state)                   |
| **Channels** | AMQP channel details per connection                                |
| **Exchanges**| List / create / delete exchanges (direct, topic, fanout)           |
| **Queues**   | Browse queues, pending messages, consumers, publish/consume test   |
| **Admin**    | Manage users, vhosts, permissions, policies                        |

#### Key actions

```
Create a queue:
  Queues → "Add a new queue"
  Name: my_queue
  Durability: Durable ✓
  Arguments: x-queue-type = quorum   ← Recommended for RabbitMQ 4.x

Publish a test message:
  Queues → my_queue → "Publish message"
  Payload: {"hello": "world"}

Peek at messages without consuming:
  Queues → my_queue → "Get messages" → Ack mode: Nack

Create a user:
  Admin → Users → "Add a user"
  Tags: management (UI access only) or administrator

Enable real-time refresh:
  Overview → "Update every 5 seconds" (bottom of the page)
```

### 2. RedisInsight — `localhost:5540`

**The official Redis Labs GUI — the most complete tool for inspecting and debugging Redis.**

#### First connection

1. Open http://localhost:5540
2. Accept the EULA if prompted
3. Click **"+ Add Redis Database"**
4. Fill in:

   | Field    | Value                                                                  |
   |----------|------------------------------------------------------------------------|
   | Host     | `host.docker.internal` (macOS/Windows) or `redis` (intra-Docker)      |
   | Port     | `6379`                                                                 |
   | Username | `admin`                                                                |
   | Password | your `REDIS_PASSWORD`                                                  |
   | Name     | `Redis Production`                                                     |

5. Click **"Add Redis Database"**

> On macOS: use `host.docker.internal` — this DNS name resolves to your host machine
> from inside a Docker container.

#### Key features

| Section        | What it does                                                       |
|----------------|--------------------------------------------------------------------|
| **Browser**    | Browse all keys by type (String, Hash, List, Set, ZSet)            |
| **Workbench**  | Run Redis commands directly (built-in CLI)                         |
| **Profiler**   | Record ALL commands in real time (debugging)                       |
| **Memory**     | Analyze which keys consume the most memory                         |
| **Slow Log**   | View commands that exceeded the threshold (> 10ms as configured)   |
| **Pub/Sub**    | Subscribe to channels and publish messages                         |

#### Useful commands in Workbench

```redis
-- Full server info
INFO all

-- Memory usage
INFO memory

-- List connected clients
CLIENT LIST

-- Check active config
CONFIG GET maxmemory
CONFIG GET maxmemory-policy

-- Scan keys safely (never use KEYS * in production)
SCAN 0 MATCH * COUNT 100

-- View slow log
SLOWLOG GET 10

-- Command statistics
COMMAND STATS
```


### 3. RabbitScout — `localhost:3001`

**Modern open source RabbitMQ dashboard (Next.js) — a clean alternative to the Management UI.**

#### Login

1. Open http://localhost:3001
2. Fill in:

   | Field    | Value                     |
   |----------|---------------------------|
   | Host     | `localhost`               |
   | Port     | `15672`                   |
   | Username | `admin`                   |
   | Password | your `RABBITMQ_PASSWORD`  |

3. Connect

#### What RabbitScout adds over the Management UI

- Built-in **dark mode**
- Smooth real-time charts (messages in/out/s)
- Fast queue search
- Condensed view of exchanges and bindings
- Faster interface for environments with many queues


### 4. Prometheus — `localhost:9090`

**Metrics engine — verify that all scrapers are running correctly.**

#### Check that scrapers are UP

1. Open http://localhost:9090/targets
2. Verify all targets show **UP**:
   - `redis` → `redis-exporter:9121`
   - `rabbitmq` → `rabbitmq:15692`
   - `prometheus` → `localhost:9090`

If a target is DOWN:

```bash
# Hot-reload Prometheus config without restart
curl -X POST http://localhost:9090/-/reload

# Check Redis metrics directly
curl http://localhost:9121/metrics | grep redis_up

# Check RabbitMQ metrics directly
curl http://localhost:15692/metrics | grep rabbitmq_up
```

#### Useful PromQL queries

```promql
# Redis — memory used (bytes)
redis_memory_used_bytes

# Redis — commands per second
rate(redis_commands_total[1m])

# Redis — cache hit ratio
redis_keyspace_hits_total / (redis_keyspace_hits_total + redis_keyspace_misses_total)

# Redis — keys per database
redis_db_keys{db="db0"}

# Redis — active client connections
redis_connected_clients

# RabbitMQ — total queued messages
sum(rabbitmq_queue_messages)

# RabbitMQ — published messages per second
rate(rabbitmq_channel_messages_published_total[1m])

# RabbitMQ — active consumers
sum(rabbitmq_queue_consumers)

# RabbitMQ — node memory usage
rabbitmq_process_resident_memory_bytes
```


### 5. Grafana — `localhost:3002`

**Visual dashboards for Redis and RabbitMQ, auto-provisioned.**

#### Login

1. Open http://localhost:3002
2. Username: `admin` / Password: your `GF_ADMIN_PASSWORD`

#### Verify Prometheus is connected

`Connections` → `Data Sources` → `Prometheus` → **"Save & Test"** → should show

#### Load dashboards manually (if not auto-loaded)

1. `Dashboards` → **"+ Import"**
2. Dashboard ID: `763` (Redis) → `Load`
3. Select datasource `Prometheus` → **Import**
4. Repeat with ID `10991` (RabbitMQ)

#### Available dashboards

**Redis — Dashboard #763**
```
Key metrics:
  ├── Uptime / Version
  ├── Memory used vs maxmemory
  ├── Hit Rate (cache efficiency)
  ├── Commands/s (total & per command)
  ├── Connected clients
  ├── Keyspace (keys per DB)
  ├── Evictions / Expirations
  ├── RDB & AOF status
  └── Replication lag
```

**RabbitMQ — Dashboard #10991 (official RabbitMQ team)**
```
Key metrics:
  ├── Messages published / delivered / acknowledged / s
  ├── Queues: ready, unacked, total messages
  ├── Connections & channels
  ├── Memory & disk usage
  ├── Error rates
  ├── Node health (alarms)
  └── Erlang processes
```

#### Set up Grafana alerts

`Dashboards` → Click a panel → `Edit` → **"Alert"** tab
- Redis memory threshold: `redis_memory_used_bytes > 400000000` (400MB)
- RabbitMQ queue too full: `rabbitmq_queue_messages > 10000`


## Service Configuration

### Redis — `redis/redis.conf` summary

| Parameter                | Value           | Effect                                       |
|--------------------------|-----------------|----------------------------------------------|
| `maxmemory`              | `512mb`         | Hard limit — prevents OOM kills              |
| `maxmemory-policy`       | `allkeys-lru`   | LRU eviction on all keys                     |
| `appendonly`             | `yes`           | AOF enabled — maximum durability             |
| `appendfsync`            | `everysec`      | Flush to disk every second                   |
| `save 900 1`             | snapshot        | RDB + AOF = recommended hybrid strategy      |
| `lazyfree-lazy-eviction` | `yes`           | Background memory release                    |

### RabbitMQ — `rabbitmq/rabbitmq.conf` summary

| Parameter                            | Value    | Effect                                          |
|--------------------------------------|----------|-------------------------------------------------|
| `vm_memory_high_watermark.relative`  | `0.6`    | Blocks publishers at 60% RAM usage             |
| `disk_free_limit.absolute`           | `2GB`    | Blocks publishers if free disk < 2GB           |
| `heartbeat`                          | `60`     | Detects dead connections every 60s              |
| `hostname` (compose)                 | fixed    | CRITICAL — data persistence across restarts     |


## Useful Commands

### Container management

```bash
# Start everything
docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d

# Follow logs in real time
docker compose logs -f redis
docker compose logs -f rabbitmq
docker compose -f docker-compose.monitoring.yml logs -f grafana

# Restart a service
docker compose restart redis
docker compose restart rabbitmq

# Stop without data loss
docker compose -f docker-compose.yml -f docker-compose.monitoring.yml down

# Stop and delete all volumes (⚠ all data will be lost)
docker compose -f docker-compose.yml -f docker-compose.monitoring.yml down -v
```

### Redis

```bash
# Ping / connection test
docker exec redis redis-cli -a $REDIS_PASSWORD ping

# Interactive admin shell
docker exec -it redis redis-cli -a $REDIS_PASSWORD

# Memory info
docker exec redis redis-cli -a $REDIS_PASSWORD INFO memory

# Trigger a manual RDB snapshot
docker exec redis redis-cli -a $REDIS_PASSWORD BGSAVE

# Manual backup of dump.rdb
docker cp redis:/data/dump.rdb ./backup-redis-$(date +%Y%m%d-%H%M).rdb

# List connected clients
docker exec redis redis-cli -a $REDIS_PASSWORD CLIENT LIST

# Monitor all commands in real time (use with care in production)
docker exec redis redis-cli -a $REDIS_PASSWORD MONITOR

# Flush a database (⚠ destructive)
docker exec redis redis-cli -a $REDIS_PASSWORD -n 1 FLUSHDB
```

### RabbitMQ

```bash
# Ping / connection test
docker exec rabbitmq rabbitmq-diagnostics -q ping

# List queues with stats
docker exec rabbitmq rabbitmqctl list_queues name messages consumers durable

# List active connections
docker exec rabbitmq rabbitmqctl list_connections user peer_host state

# Purge a queue (⚠ destructive)
docker exec rabbitmq rabbitmqctl purge_queue my_queue

# Create a vhost
docker exec rabbitmq rabbitmqctl add_vhost my_vhost
docker exec rabbitmq rabbitmqctl set_permissions -p my_vhost admin ".*" ".*" ".*"

# Node status
docker exec rabbitmq rabbitmqctl status

# List enabled plugins
docker exec rabbitmq rabbitmq-plugins list --enabled

# Enable a plugin at runtime (no restart needed)
docker exec rabbitmq rabbitmq-plugins enable rabbitmq_shovel
```


## Production Checklist

### Required before going to production

- [ ] macOS: nothing to do · Linux: `vm.overcommit_memory = 1` set (see Step 1)
- [ ] All passwords changed in `.env`
- [ ] Passwords changed in `redis/users.acl` (admin, appuser, readonly)
- [ ] `REDIS_EXPORTER_PASSWORD` matches the `appuser` password in `users.acl`
- [ ] Grafana dashboards downloaded and patched (`sed`)
- [ ] All Prometheus targets **UP** at http://localhost:9090/targets
- [ ] RedisInsight connected to Redis
- [ ] `.env` added to `.gitignore` (never commit secrets)

### Recommended

- [ ] Docker volumes on SSD (AOF I/O is critical for Redis)
- [ ] Memory limits adjusted to your actual RAM (`REDIS_MEM_LIMIT`, `RABBITMQ_MEM_LIMIT`)
- [ ] Ports bound to `127.0.0.1` only (or behind a reverse proxy + TLS)
- [ ] Automated backups scheduled (cron)
- [ ] Grafana alerts configured (memory thresholds, queue depth)
- [ ] TLS enabled if network-exposed (`rabbitmq.conf` TLS section, Redis `tls-*`)


## Troubleshooting

### Redis won't start

```bash
docker compose logs redis

# Common issues:
# 1. "Can't save in background: fork: Cannot allocate memory"
#    → macOS Docker Desktop: cosmetic warning, no action needed
#    → Linux: echo "vm.overcommit_memory = 1" | sudo tee /etc/sysctl.d/99-redis.conf && sudo sysctl -p /etc/sysctl.d/99-redis.conf

# 2. "Permission denied" on volume
#    Fix:
docker compose down -v
docker volume rm redrab_redis_data
docker compose up -d redis
```

### RabbitMQ loses data on restart

```bash
# Verify the hostname is fixed
docker inspect rabbitmq | grep Hostname

# Should return: "rabbitmq-server"
# If not → check docker-compose.yml → hostname: rabbitmq-server
```

### Grafana shows no data

```bash
# 1. Check Prometheus is scraping
open http://localhost:9090/targets
# All targets must show State: UP

# 2. Force Prometheus config reload
curl -X POST http://localhost:9090/-/reload

# 3. Check Redis metrics
curl http://localhost:9121/metrics | grep "redis_up"
# Should return: redis_up 1

# 4. Check RabbitMQ metrics
curl http://localhost:15692/metrics | grep "rabbitmq_identity_info"

# 5. In Grafana: adjust the time range in the top right
# → "Last 15 minutes" or "Last 1 hour"
```

### redis_exporter can't connect to Redis

```bash
# Verify REDIS_EXPORTER_PASSWORD matches the "appuser" password in users.acl
docker compose -f docker-compose.monitoring.yml logs redis-exporter

# If you see "WRONGPASS" → the password in .env doesn't match users.acl
nano redis/users.acl   # update the appuser password
nano .env              # set the same value for REDIS_EXPORTER_PASSWORD
docker compose restart redis redis-exporter
```

### Grafana port 3002 unreachable

```bash
# Check the container is running
docker ps | grep grafana

# Check the port binding
docker port grafana
# Should return: 3000/tcp -> 127.0.0.1:3002
```

### "network infra-backend could not be found"

This happens when the monitoring file is started **alone** without the main file.

```bash
# Wrong:
docker compose -f docker-compose.monitoring.yml up -d

# Always merge both files:
docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d
```
