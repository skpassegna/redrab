# :whale: Redis + RabbitMQ — Infrastructure de production & stack de supervision

> Configuration Docker Compose prête pour la production · Construit **2026-03-10**

## Table des matières

1. [Aperçu](#aperçu)
2. [Structure du projet](#structure-du-projet)
3. [Démarrage rapide](#démarrage-rapide)
4. [Ports et URL](#ports-et-url)
5. [URIs de connexion](#uris-de-connexion)

   * [Redis](#redis)
   * [RabbitMQ](#rabbitmq)
6. [Interfaces Web — Guides d'utilisation](#interfaces-web--guides-dutilisation)

   * [RabbitMQ Management UI](#1-rabbitmq-management-ui---localhost15672)
   * [RedisInsight](#2-redisinsight---localhost5540)
   * [RabbitScout](#3-rabbitscout---localhost3001)
   * [Prometheus](#4-prometheus---localhost9090)
   * [Grafana](#5-grafana---localhost3002)
7. [Configuration des services](#configuration-des-services)
8. [Commandes utiles](#commandes-utiles)
9. [Checklist avant production](#checklist-avant-production)
10. [Dépannage](#dépannage)

---

## Aperçu

```
┌─────────────────────────────────────────────────────────────────────┐
│                           VOS PROJETS                               │
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

Interfaces web directes :
  RedisInsight  :5540   ← GUI officiel Redis
  RabbitMQ UI   :15672  ← Interface de management native
  RabbitScout   :3001   ← GUI RabbitMQ moderne
```

## Structure du projet

```
redrab/
├── docker-compose.yml                        ← Infra : Redis + RabbitMQ
├── docker-compose.monitoring.yml             ← Supervision : Prometheus, Grafana, UIs
├── .env.example                              ← Modèle de variables (cp → .env)
├── .env                                      ← Secrets réels (⚠ ne jamais commiter)
│
├── redis/
│   ├── redis.conf                            ← Configuration Redis 7.x pour production
│   │                                             AOF + RDB + ACL + réglages
│   └── users.acl                             ← ACL des utilisateurs
│                                                 (admin, appuser, readonly)
│
├── rabbitmq/
│   ├── rabbitmq.conf                         ← Configuration RabbitMQ 4.x pour production
│   │                                             mémoire, disque, heartbeat, Prometheus
│   └── enabled_plugins                       ← plugins activés : management + prometheus
│
├── prometheus/
│   └── prometheus.yml                        ← Scrapes : Redis :9121 + RabbitMQ :15692
│
└── grafana/
    └── provisioning/
        ├── datasources/
        │   └── datasources.yml               ← Connexion automatique à Prometheus
        └── dashboards/
            ├── dashboards.yml                ← Chargeur automatique de dashboards
            ├── redis.json                    ← ⬇ À télécharger (Dashboard #763)
            └── rabbitmq-overview.json        ← ⬇ À télécharger (Dashboard #10991)
```

## Démarrage rapide

### Étape 1 — Prérequis système

#### macOS (Docker Desktop) — Rien à faire

Docker Desktop inclut une VM Linux interne (LinuxKit) qui gère déjà
`vm.overcommit_memory` et les Transparent Huge Pages. **Passez directement à l'Étape 2.**

Redis peut afficher des avertissements cosmétiques du noyau dans ses logs — c'est attendu
et sans danger sur Docker Desktop macOS.

```bash
# Vérifiez simplement que Docker Desktop fonctionne
docker info | grep "Operating System"
# → Operating System: Docker Desktop
```

#### Linux — Serveur de production / VPS (UNE FOIS UNIQUEMENT)

```bash
# Overcommit mémoire — requis pour les sauvegardes background AOF/RDB
echo "vm.overcommit_memory = 1" | sudo tee /etc/sysctl.d/99-redis.conf
sudo sysctl -p /etc/sysctl.d/99-redis.conf

# Désactiver Transparent Huge Pages (réduit la latence Redis)
echo never | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
```

### Étape 2 — Configurer les secrets

```bash
cp .env.example .env
nano .env
```

Vous **devez** renseigner :

* `REDIS_PASSWORD`
* `REDIS_EXPORTER_PASSWORD` (doit correspondre au mot de passe `appuser` dans `redis/users.acl`)
* `RABBITMQ_PASSWORD`
* `GF_ADMIN_PASSWORD`

Puis mettez à jour les mots de passe dans `redis/users.acl` :

```bash
nano redis/users.acl
# Remplacez CHANGE_ME_ADMIN_PASSWORD, CHANGE_ME_APP_PASSWORD, CHANGE_ME_READONLY_PASSWORD
```

### Étape 3 — Télécharger les dashboards Grafana

```bash
# Dashboard Redis (ID 763)
curl -o grafana/provisioning/dashboards/redis.json \
  "https://grafana.com/api/dashboards/763/revisions/latest/download"

# Dashboard RabbitMQ Overview (ID 10991 — équipe officielle RabbitMQ)
curl -o grafana/provisioning/dashboards/rabbitmq-overview.json \
  "https://grafana.com/api/dashboards/10991/revisions/latest/download"

# Corriger le placeholder de datasource dans les JSON téléchargés
# macOS :
sed -i '' 's/\${DS_PROMETHEUS}/prometheus-ds/g' grafana/provisioning/dashboards/*.json
# Linux :
sed -i 's/\${DS_PROMETHEUS}/prometheus-ds/g' grafana/provisioning/dashboards/*.json
```

### Étape 4 — Démarrer

```bash
# Démarrer l'ensemble (recommandé)
docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d

# Vérifier que tous les services sont UP
docker compose -f docker-compose.yml -f docker-compose.monitoring.yml ps
```

## Ports et URL

| Service             | Port hôte | URL                                                              | Remarques                               |
| ------------------- | --------- | ---------------------------------------------------------------- | --------------------------------------- |
| Redis RESP          | `6379`    | —                                                                | Connexion directe depuis l'application  |
| RabbitMQ AMQP       | `5672`    | —                                                                | Connexion directe depuis l'application  |
| **RabbitMQ UI**     | `15672`   | [http://localhost:15672](http://localhost:15672)                 | Interface native de management RabbitMQ |
| RabbitMQ Prometheus | `15692`   | [http://localhost:15692/metrics](http://localhost:15692/metrics) | Metrics brutes (scrape Prometheus)      |
| redis_exporter      | `9121`    | [http://localhost:9121/metrics](http://localhost:9121/metrics)   | Metrics Redis brutes                    |
| **RedisInsight**    | `5540`    | [http://localhost:5540](http://localhost:5540)                   | GUI officiel Redis                      |
| **RabbitScout**     | `3001`    | [http://localhost:3001](http://localhost:3001)                   | GUI RabbitMQ open source moderne        |
| **Prometheus**      | `9090`    | [http://localhost:9090](http://localhost:9090)                   | Interface de requêtes PromQL            |
| **Grafana**         | `3002`    | [http://localhost:3002](http://localhost:3002)                   | Dashboards                              |

> Tous les ports sont liés à `127.0.0.1` par défaut — accès local uniquement.
> Pour une exposition distante, utilisez un reverse proxy (Nginx, Caddy) avec TLS.

## URIs de connexion

> Les exemples ci-dessous utilisent les valeurs de `.env.example`.
> Remplacez les mots de passe par vos valeurs réelles.

### Redis

#### Format standard d'URI

```
redis://<user>:<password>@<host>:<port>/<db>
```

#### URIs selon le contexte

```bash
# ── Depuis un projet HORS Docker (processus local, scripts, etc.) ────────
redis://appuser:CHANGE_ME_APP_PASSWORD@localhost:6379/0

# ── Depuis un conteneur sur le MÊME réseau Docker (infra-backend) ───────
redis://appuser:CHANGE_ME_APP_PASSWORD@redis:6379/0

# ── Utilisateur admin (maintenance, migrations) ─────────────────────────
redis://admin:CHANGE_ME_ADMIN_PASSWORD@localhost:6379/0

# ── Utilisateur readonly (analytique, accès en lecture seule) ──────────
redis://readonly:CHANGE_ME_READONLY_PASSWORD@localhost:6379/0
```

#### Variables d'environnement pour votre projet

```bash
REDIS_URL=redis://appuser:CHANGE_ME_APP_PASSWORD@localhost:6379/0
# ou forme split :
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_USER=appuser
REDIS_PASSWORD=CHANGE_ME_APP_PASSWORD
REDIS_DB=0
```

### RabbitMQ

#### Format standard d'URI (AMQP)

```
amqp://<user>:<password>@<host>:<port>/<vhost>
amqps://<user>:<password>@<host>:<port>/<vhost>   ← avec TLS
```

> Le vhost racine `/` doit être encodé en URL comme `%2F` dans l'URI.

#### URIs selon le contexte

```bash
# ── Depuis un projet HORS Docker (processus local, scripts, etc.) ────────
amqp://admin:CHANGE_ME_RABBIT_PASSWORD@localhost:5672/%2F

# ── Depuis un conteneur sur le MÊME réseau Docker (infra-backend) ───────
amqp://admin:CHANGE_ME_RABBIT_PASSWORD@rabbitmq:5672/%2F

# ── Avec un vhost personnalisé ──────────────────────────────────────────
amqp://admin:CHANGE_ME_RABBIT_PASSWORD@localhost:5672/my_vhost
```

#### Variables d'environnement pour votre projet

```bash
RABBITMQ_URL=amqp://admin:CHANGE_ME_RABBIT_PASSWORD@localhost:5672
RABBITMQ_HOST=localhost
RABBITMQ_PORT=5672
RABBITMQ_USER=admin
RABBITMQ_PASSWORD=CHANGE_ME_RABBIT_PASSWORD
RABBITMQ_VHOST=/
```

## Interfaces Web — Guides d'utilisation

### 1. RabbitMQ Management UI — `localhost:15672`

**L'interface web native officielle RabbitMQ, incluse sans configuration supplémentaire.**

#### Connexion

1. Ouvrez [http://localhost:15672](http://localhost:15672)
2. Nom d'utilisateur : `admin` / Mot de passe : votre `RABBITMQ_PASSWORD` depuis `.env`

#### Navigation

| Onglet          | Usage principal                                                            |
| --------------- | -------------------------------------------------------------------------- |
| **Overview**    | Vue globale : messages/s, connexions, channels, mémoire, disque            |
| **Connections** | Toutes les connexions ouvertes (IP, utilisateur, vhost, état)              |
| **Channels**    | Détails des channels AMQP par connexion                                    |
| **Exchanges**   | Lister / créer / supprimer des exchanges (direct, topic, fanout)           |
| **Queues**      | Parcourir les queues, messages en attente, consumers, test publish/consume |
| **Admin**       | Gérer utilisateurs, vhosts, permissions, policies                          |

#### Actions clés

```
Créer une queue :
  Queues → "Add a new queue"
  Name: my_queue
  Durability: Durable ✓
  Arguments: x-queue-type = quorum   ← Recommandé pour RabbitMQ 4.x

Publier un message de test :
  Queues → my_queue → "Publish message"
  Payload: {"hello": "world"}

Consulter des messages sans consommer :
  Queues → my_queue → "Get messages" → Ack mode: Nack

Créer un utilisateur :
  Admin → Users → "Add a user"
  Tags: management (accès UI uniquement) ou administrator

Activer le rafraîchissement temps réel :
  Overview → "Update every 5 seconds" (en bas de la page)
```

### 2. RedisInsight — `localhost:5540`

**GUI officiel Redis Labs — l'outil le plus complet pour inspecter et déboguer Redis.**

#### Première connexion

1. Ouvrez [http://localhost:5540](http://localhost:5540)

2. Acceptez l'EULA si demandé

3. Cliquez sur **"+ Add Redis Database"**

4. Remplissez :

   | Champ    | Valeur                                                           |
   | -------- | ---------------------------------------------------------------- |
   | Host     | `host.docker.internal` (macOS/Windows) ou `redis` (intra-Docker) |
   | Port     | `6379`                                                           |
   | Username | `admin`                                                          |
   | Password | votre `REDIS_PASSWORD`                                           |
   | Name     | `Redis Production`                                               |

5. Cliquez sur **"Add Redis Database"**

> Sur macOS : utilisez `host.docker.internal` — ce nom DNS résout vers votre machine hôte
> depuis l'intérieur d'un conteneur Docker.

#### Fonctions clés

| Section       | Ce que cela fait                                                   |
| ------------- | ------------------------------------------------------------------ |
| **Browser**   | Parcourir toutes les clés par type (String, Hash, List, Set, ZSet) |
| **Workbench** | Exécuter des commandes Redis directement (CLI intégré)             |
| **Profiler**  | Enregistrer TOUTES les commandes en temps réel (débogage)          |
| **Memory**    | Analyser quelles clés consomment le plus de mémoire                |
| **Slow Log**  | Voir les commandes dépassant le seuil (> 10ms tel que configuré)   |
| **Pub/Sub**   | S'abonner à des channels et publier des messages                   |

#### Commandes utiles dans Workbench

```redis
-- Informations complètes du serveur
INFO all

-- Utilisation mémoire
INFO memory

-- Lister les clients connectés
CLIENT LIST

-- Vérifier la config active
CONFIG GET maxmemory
CONFIG GET maxmemory-policy

-- Scanner les clés en toute sécurité (éviter KEYS * en production)
SCAN 0 MATCH * COUNT 100

-- Voir le slow log
SLOWLOG GET 10

-- Statistiques des commandes
COMMAND STATS
```

### 3. RabbitScout — `localhost:3001`

**Dashboard RabbitMQ open source moderne (Next.js) — alternative plus épurée à la Management UI.**

#### Connexion

1. Ouvrez [http://localhost:3001](http://localhost:3001)

2. Remplissez :

   | Champ    | Valeur                    |
   | -------- | ------------------------- |
   | Host     | `localhost`               |
   | Port     | `15672`                   |
   | Username | `admin`                   |
   | Password | votre `RABBITMQ_PASSWORD` |

3. Connectez-vous

#### Ce que RabbitScout apporte par rapport à la Management UI

* **Dark mode** intégré
* Graphiques temps réel fluides (messages in/out/s)
* Recherche de queue rapide
* Vue condensée des exchanges et bindings
* Interface plus réactive pour les environnements avec beaucoup de queues

### 4. Prometheus — `localhost:9090`

**Moteur de métriques — vérifier que tous les scrapers fonctionnent correctement.**

#### Vérifier que les scrapers sont UP

1. Ouvrez [http://localhost:9090/targets](http://localhost:9090/targets)
2. Vérifiez que toutes les cibles affichent **UP** :

   * `redis` → `redis-exporter:9121`
   * `rabbitmq` → `rabbitmq:15692`
   * `prometheus` → `localhost:9090`

Si une cible est DOWN :

```bash
# Recharger la config Prometheus à chaud sans redémarrage
curl -X POST http://localhost:9090/-/reload

# Vérifier directement les metrics Redis
curl http://localhost:9121/metrics | grep redis_up

# Vérifier directement les metrics RabbitMQ
curl http://localhost:15692/metrics | grep rabbitmq_up
```

#### Requêtes PromQL utiles

```promql
# Redis — mémoire utilisée (octets)
redis_memory_used_bytes

# Redis — commandes par seconde
rate(redis_commands_total[1m])

# Redis — taux de cache hit
redis_keyspace_hits_total / (redis_keyspace_hits_total + redis_keyspace_misses_total)

# Redis — clés par base de données
redis_db_keys{db="db0"}

# Redis — clients connectés actifs
redis_connected_clients

# RabbitMQ — total de messages en file
sum(rabbitmq_queue_messages)

# RabbitMQ — messages publiés par seconde
rate(rabbitmq_channel_messages_published_total[1m])

# RabbitMQ — consommateurs actifs
sum(rabbitmq_queue_consumers)

# RabbitMQ — mémoire utilisée par le process
rabbitmq_process_resident_memory_bytes
```

### 5. Grafana — `localhost:3002`

**Dashboards visuels pour Redis et RabbitMQ, provisionnés automatiquement.**

#### Connexion

1. Ouvrez [http://localhost:3002](http://localhost:3002)
2. Nom d'utilisateur : `admin` / Mot de passe : votre `GF_ADMIN_PASSWORD`

#### Vérifier la connexion à Prometheus

`Connections` → `Data Sources` → `Prometheus` → **"Save & Test"** → devrait afficher réussite

#### Charger les dashboards manuellement (si non auto-chargés)

1. `Dashboards` → **"+ Import"**
2. ID du dashboard : `763` (Redis) → `Load`
3. Sélectionnez la datasource `Prometheus` → **Import**
4. Répétez avec l'ID `10991` (RabbitMQ)

#### Dashboards disponibles

**Redis — Dashboard #763**

```
Indicateurs clés :
  ├── Uptime / Version
  ├── Mémoire utilisée vs maxmemory
  ├── Taux de hit (efficacité du cache)
  ├── Commands/s (total & par commande)
  ├── Clients connectés
  ├── Keyspace (clés par DB)
  ├── Evictions / Expirations
  ├── État RDB & AOF
  └── Latence de réplication
```

**RabbitMQ — Dashboard #10991 (équipe officielle RabbitMQ)**

```
Indicateurs clés :
  ├── Messages publiés / délivrés / acquittés / s
  ├── Queues : ready, unacked, total messages
  ├── Connexions & channels
  ├── Utilisation mémoire & disque
  ├── Taux d'erreur
  ├── Santé du nœud (alarms)
  └── Processus Erlang
```

#### Configurer des alertes Grafana

`Dashboards` → Cliquer sur un panneau → `Edit` → onglet **"Alert"**

* Seuil mémoire Redis : `redis_memory_used_bytes > 400000000` (400MB)
* Queue RabbitMQ trop pleine : `rabbitmq_queue_messages > 10000`

## Configuration des services

### Redis — résumé de `redis/redis.conf`

| Paramètre                | Valeur        | Effet                                     |
| ------------------------ | ------------- | ----------------------------------------- |
| `maxmemory`              | `512mb`       | Limite stricte — évite les OOM kills      |
| `maxmemory-policy`       | `allkeys-lru` | Éviction LRU sur toutes les clés          |
| `appendonly`             | `yes`         | AOF activé — durabilité maximale          |
| `appendfsync`            | `everysec`    | Flush sur disque chaque seconde           |
| `save 900 1`             | snapshot      | RDB + AOF = stratégie hybride recommandée |
| `lazyfree-lazy-eviction` | `yes`         | Libération mémoire en arrière-plan        |

### RabbitMQ — résumé de `rabbitmq/rabbitmq.conf`

| Paramètre                           | Valeur | Effet                                                         |
| ----------------------------------- | ------ | ------------------------------------------------------------- |
| `vm_memory_high_watermark.relative` | `0.6`  | Bloque les publishers à 60% d'utilisation RAM                 |
| `disk_free_limit.absolute`          | `2GB`  | Bloque les publishers si l'espace libre < 2GB                 |
| `heartbeat`                         | `60`   | Détecte les connexions mortes toutes les 60s                  |
| `hostname` (compose)                | fixé   | CRITIQUE — persistance des données à travers les redémarrages |

## Commandes utiles

### Gestion des conteneurs

```bash
# Démarrer l'ensemble
docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d

# Suivre les logs en temps réel
docker compose logs -f redis
docker compose logs -f rabbitmq
docker compose -f docker-compose.monitoring.yml logs -f grafana

# Redémarrer un service
docker compose restart redis
docker compose restart rabbitmq

# Arrêter sans perte de données
docker compose -f docker-compose.yml -f docker-compose.monitoring.yml down

# Arrêter et supprimer tous les volumes (⚠ toutes les données seront perdues)
docker compose -f docker-compose.yml -f docker-compose.monitoring.yml down -v
```

### Redis

```bash
# Ping / test de connexion
docker exec redis redis-cli -a $REDIS_PASSWORD ping

# Shell admin interactif
docker exec -it redis redis-cli -a $REDIS_PASSWORD

# Info mémoire
docker exec redis redis-cli -a $REDIS_PASSWORD INFO memory

# Forcer un snapshot RDB manuel
docker exec redis redis-cli -a $REDIS_PASSWORD BGSAVE

# Sauvegarde manuelle de dump.rdb
docker cp redis:/data/dump.rdb ./backup-redis-$(date +%Y%m%d-%H%M).rdb

# Lister les clients connectés
docker exec redis redis-cli -a $REDIS_PASSWORD CLIENT LIST

# Monitorer toutes les commandes en temps réel (à utiliser avec prudence en prod)
docker exec redis redis-cli -a $REDIS_PASSWORD MONITOR

# Vider une base (⚠ destructif)
docker exec redis redis-cli -a $REDIS_PASSWORD -n 1 FLUSHDB
```

### RabbitMQ

```bash
# Ping / test de connexion
docker exec rabbitmq rabbitmq-diagnostics -q ping

# Lister les queues avec stats
docker exec rabbitmq rabbitmqctl list_queues name messages consumers durable

# Lister les connexions actives
docker exec rabbitmq rabbitmqctl list_connections user peer_host state

# Purger une queue (⚠ destructif)
docker exec rabbitmq rabbitmqctl purge_queue my_queue

# Créer un vhost
docker exec rabbitmq rabbitmqctl add_vhost my_vhost
docker exec rabbitmq rabbitmqctl set_permissions -p my_vhost admin ".*" ".*" ".*"

# État du nœud
docker exec rabbitmq rabbitmqctl status

# Lister les plugins activés
docker exec rabbitmq rabbitmq-plugins list --enabled

# Activer un plugin à la volée (pas de redémarrage nécessaire)
docker exec rabbitmq rabbitmq-plugins enable rabbitmq_shovel
```

## Checklist avant production

### Obligatoire avant mise en production

* [ ] macOS : rien à faire · Linux : `vm.overcommit_memory = 1` configuré (voir Étape 1)
* [ ] Tous les mots de passe modifiés dans `.env`
* [ ] Mots de passe modifiés dans `redis/users.acl` (admin, appuser, readonly)
* [ ] `REDIS_EXPORTER_PASSWORD` correspond au mot de passe `appuser` dans `users.acl`
* [ ] Dashboards Grafana téléchargés et patchés (`sed`)
* [ ] Tous les targets Prometheus **UP** sur [http://localhost:9090/targets](http://localhost:9090/targets)
* [ ] RedisInsight connecté à Redis
* [ ] `.env` ajouté à `.gitignore` (ne jamais committer des secrets)

### Recommandé

* [ ] Volumes Docker sur SSD (I/O AOF critique pour Redis)
* [ ] Limites mémoire ajustées à la RAM réelle (`REDIS_MEM_LIMIT`, `RABBITMQ_MEM_LIMIT`)
* [ ] Ports liés à `127.0.0.1` uniquement (ou exposés derrière un reverse proxy + TLS)
* [ ] Sauvegardes automatisées planifiées (cron)
* [ ] Alertes Grafana configurées (seuils mémoire, profondeur de queue)
* [ ] TLS activé si exposition réseau (`rabbitmq.conf` section TLS, Redis `tls-*`)

## Dépannage

### Redis ne démarre pas

```bash
docker compose logs redis

# Problèmes courants :
# 1. "Can't save in background: fork: Cannot allocate memory"
#    → macOS Docker Desktop : avertissement cosmétique, pas d'action nécessaire
#    → Linux : echo "vm.overcommit_memory = 1" | sudo tee /etc/sysctl.d/99-redis.conf && sudo sysctl -p /etc/sysctl.d/99-redis.conf

# 2. "Permission denied" sur le volume
#    Correction :
docker compose down -v
docker volume rm redrab_redis_data
docker compose up -d redis
```

### RabbitMQ perd des données au redémarrage

```bash
# Vérifier que le hostname est fixe
docker inspect rabbitmq | grep Hostname

# Devrait retourner : "rabbitmq-server"
# Si non → vérifier docker-compose.yml → hostname: rabbitmq-server
```

### Grafana n'affiche pas de données

```bash
# 1. Vérifier que Prometheus scrape
open http://localhost:9090/targets
# Tous les targets doivent afficher State: UP

# 2. Forcer le rechargement de la config Prometheus
curl -X POST http://localhost:9090/-/reload

# 3. Vérifier les metrics Redis
curl http://localhost:9121/metrics | grep "redis_up"
# Devrait retourner : redis_up 1

# 4. Vérifier les metrics RabbitMQ
curl http://localhost:15692/metrics | grep "rabbitmq_identity_info"

# 5. Dans Grafana : ajuster la plage temporelle en haut à droite
# → "Last 15 minutes" ou "Last 1 hour"
```

### redis_exporter ne peut pas se connecter à Redis

```bash
# Vérifier que REDIS_EXPORTER_PASSWORD correspond au mot de passe "appuser" dans users.acl
docker compose -f docker-compose.monitoring.yml logs redis-exporter

# Si vous voyez "WRONGPASS" → le mot de passe dans .env ne correspond pas à users.acl
nano redis/users.acl   # mettre à jour le mot de passe appuser
nano .env              # définir la même valeur pour REDIS_EXPORTER_PASSWORD
docker compose restart redis redis-exporter
```

### Le port Grafana 3002 est inaccessible

```bash
# Vérifier que le conteneur tourne
docker ps | grep grafana

# Vérifier le binding du port
docker port grafana
# Devrait retourner : 3000/tcp -> 127.0.0.1:3002
```

### "network infra-backend could not be found"

Cela survient lorsque le fichier de monitoring est démarré **seul** sans le fichier principal.

```bash
# Mauvais :
docker compose -f docker-compose.monitoring.yml up -d

# Toujours fusionner les deux fichiers :
docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d
```