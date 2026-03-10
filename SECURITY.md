# Security Policy

## Supported Versions

This project is a Docker Compose infrastructure stack. Security fixes are applied
to the **latest version** on the `main` branch only.

## Reporting a Vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

If you discover a security issue — such as a dangerous default configuration,
an exposed secret, or a component with a known CVE — please report it privately:

1. Go to the [Security tab](../../security/advisories/new) of this repository
2. Click **"Report a vulnerability"**
3. Describe the issue clearly (see template below)

You can expect an acknowledgement within **72 hours**.

## What to Include in Your Report

```
Component affected:     (e.g. redis/users.acl, docker-compose.yml, rabbitmq.conf)
Type of issue:          (e.g. exposed credential, insecure default, CVE in image)
Impact:                 (what could an attacker do?)
Steps to reproduce:     (minimal config or command that demonstrates the issue)
Suggested fix:          (optional but appreciated)
```

## Security Defaults in This Project

This stack is designed with the following security defaults. If you find any of
these missing or misconfigured, that is worth reporting.

### Redis
- `user default off` — the default Redis user is disabled; all access requires explicit credentials
- ACL-based access with three separate users: `admin`, `appuser` (write), `readonly`
- `protected-mode yes` — rejects unauthenticated connections even on loopback
- All passwords are set via `.env` and `users.acl` — never hardcoded in Compose files

### RabbitMQ
- `loopback_users.guest = true` — the `guest` user is restricted to localhost only
- Custom admin credentials required via `RABBITMQ_PASSWORD` — no default `guest/guest`
- Management UI and Prometheus ports bound to `127.0.0.1` by default

### Docker Compose
- All ports are bound to `127.0.0.1` — not exposed to the network by default
- `.env` is in `.gitignore` — secrets must never be committed
- Volumes use named Docker volumes, not bind-mounted host paths

## Known Limitations

These are known trade-offs that are intentional and documented:

- **Passwords in `.env`**: passwords are stored in a plaintext `.env` file. For production
  environments with stricter requirements, consider using Docker Secrets or a vault solution.
- **No TLS by default**: TLS for Redis and RabbitMQ is included as a commented-out
  configuration block but is not enabled by default. Enable it for any network-exposed deployment.
- **redis_exporter credentials**: the exporter requires the Redis `appuser` password
  in `.env`. This is a known design constraint of Prometheus exporters.
