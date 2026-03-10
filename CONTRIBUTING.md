# Contributing to redrab

Thank you for taking the time to contribute. This project is a production-ready Docker Compose stack for Redis and RabbitMQ — contributions that improve reliability, documentation, or compatibility are very welcome.

## Table of Contents

1. [Ways to Contribute](#ways-to-contribute)
2. [Reporting a Bug](#reporting-a-bug)
3. [Suggesting an Improvement](#suggesting-an-improvement)
4. [Submitting a Pull Request](#submitting-a-pull-request)
5. [What We're Looking For](#what-were-looking-for)
6. [What's Out of Scope](#whats-out-of-scope)
7. [Style Guidelines](#style-guidelines)

## Ways to Contribute

You don't need to write code to contribute. Here are ways to help:

- **Report a bug** — something doesn't start, a command fails, a config is wrong
- **Improve documentation** — fix typos, clarify a step, add a missing detail
- **Test on different environments** — Linux distros, different Docker versions, ARM machines
- **Suggest an improvement** — a missing feature, a better default, an additional tool
- **Translate the README** — the project currently has English and French versions

## Reporting a Bug

Before opening an issue:

1. Search [existing issues](../../issues) to avoid duplicates
2. Make sure you're running the latest version of the files
3. Collect the relevant logs:

```bash
# Logs for a specific service
docker compose -f docker-compose.yml -f docker-compose.monitoring.yml logs <service-name>

# All services at once
docker compose -f docker-compose.yml -f docker-compose.monitoring.yml logs
```

Then open a [Bug Report](../../issues/new?template=bug_report.md) and fill in the template.

**Never include real passwords or secrets in your issue.**
Use placeholders like `REDACTED` or `***`.

## Suggesting an Improvement

Open a [Feature Request](../../issues/new?template=feature_request.md) and describe:

- What problem you're trying to solve
- What your proposed solution looks like
- Any alternatives you considered

## Submitting a Pull Request

### Before you start

- Check [open issues](../../issues) and [open PRs](../../pulls) to avoid duplicating work
- For significant changes, open an issue first to discuss the approach

### Process

1. Fork the repository
2. Create a branch with a descriptive name:
   ```bash
   git checkout -b fix/redis-healthcheck-acl
   git checkout -b feat/add-alertmanager
   git checkout -b docs/improve-grafana-guide
   ```
3. Make your changes
4. Test locally before submitting:
   ```bash
   # Full stack start
   docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d

   # Verify all services are healthy
   docker compose -f docker-compose.yml -f docker-compose.monitoring.yml ps

   # Check logs for errors
   docker compose -f docker-compose.yml -f docker-compose.monitoring.yml logs
   ```
5. Open a Pull Request using the PR template

## What We're Looking For

Contributions that are particularly welcome:

| Area | Examples |
|------|---------|
| **Bug fixes** | Broken configs, wrong commands, misleading docs |
| **Compatibility** | ARM64/Apple Silicon support, older Docker versions, Linux distros |
| **Security** | Better ACL defaults, TLS setup guide, secrets handling |
| **Monitoring** | Additional Grafana dashboards, Prometheus alert rules |
| **Documentation** | Clearer steps, more troubleshooting cases, translations |
| **New tools** | Additional optional services that fit the infra scope (e.g. Alertmanager) |

## What's Out of Scope

To keep the project focused and easy to maintain:

- **Application-level code** — this repo is infrastructure only, not a code library
- **Cloud-provider-specific configs** (AWS ECS, GKE, etc.) — out of scope for this Docker Compose project
- **Kubernetes manifests** — a separate project would be more appropriate
- **Unrelated services** — adding databases or services unrelated to the Redis/RabbitMQ stack

## Style Guidelines

### Docker Compose files

- Keep comments clear and in English
- Explain non-obvious choices (why a setting exists, what it prevents)
- Always use explicit image tags — never `latest` for production-critical services
- Bind ports to `127.0.0.1` by default

### Config files (`redis.conf`, `rabbitmq.conf`)

- Group settings under clearly labeled sections
- Comment every non-default value with its purpose
- No comments in `users.acl` — Redis rejects them

### Documentation

- Keep language simple and direct
- Avoid code examples tied to a specific programming language
- Both README files (English and French) should stay in sync for major changes
- Use `bash` code blocks for shell commands, plain blocks for config snippets

### Commit messages

Follow the conventional commits format:

```
fix: correct Redis healthcheck for ACL-enabled instances
feat: add Alertmanager to monitoring stack
docs: clarify Grafana dashboard download step for macOS
chore: update RabbitMQ image to 4.1
```
