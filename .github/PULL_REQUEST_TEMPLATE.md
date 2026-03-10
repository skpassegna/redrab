## What does this PR do?

<!-- A short description of the change and why it's needed -->

## Type of change

- [ ] Bug fix
- [ ] Improvement to an existing config or default
- [ ] New feature / new optional service
- [ ] Documentation update
- [ ] Security improvement

## Related issue

<!-- Link to the issue this PR addresses, if any -->
Closes #

## Testing checklist

- [ ] Full stack starts without errors:
  ```bash
  docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d
  ```
- [ ] All services are healthy:
  ```bash
  docker compose -f docker-compose.yml -f docker-compose.monitoring.yml ps
  ```
- [ ] No errors in logs:
  ```bash
  docker compose -f docker-compose.yml -f docker-compose.monitoring.yml logs
  ```
- [ ] Tested on: <!-- OS + architecture, e.g. macOS Apple Silicon / Ubuntu 24.04 x86_64 -->

## Documentation

- [ ] `README.md` updated if needed
- [ ] `README.fr.md` updated to match (for significant changes)
- [ ] `CHANGELOG.md` entry added

## Security

- [ ] No secrets, real passwords, or tokens included
- [ ] Any new default credentials use placeholder values (`CHANGE_ME_*`)
- [ ] Ports are bound to `127.0.0.1` by default if newly exposed
