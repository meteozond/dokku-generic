# dokku-generic Plan 8 — CI / Release / README

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development или superpowers:executing-plans.

**Goal:** Полноценная CI пайплайн через GitHub Actions (lint + tests на матрице Dokku), совместимая с локальным `act`. Tagged release через workflow. Расширенный README с тремя MCP-примерами и полным command reference.

**Prerequisite:** Plans 1–7.

---

## Task 1: `.github/workflows/ci.yml`

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Файл**

```yaml
name: CI

on:
  pull_request:
    branches: ["*"]
  push:
    branches: [main]

concurrency:
  group: ci-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: true

jobs:
  lint:
    name: lint
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v6
      - name: Install shellcheck
        run: sudo apt-get update && sudo apt-get install -y shellcheck
      - name: Install shfmt
        run: |
          curl -fsSL https://github.com/mvdan/sh/releases/download/v3.7.0/shfmt_v3.7.0_linux_amd64 -o /usr/local/bin/shfmt
          chmod +x /usr/local/bin/shfmt
      - name: Validate plugin.toml
        run: python3 -c "import tomllib, sys; tomllib.load(open('plugin.toml','rb'))"
      - name: Run shellcheck
        run: make shellcheck
      - name: Check formatting
        run: make shfmt

  unit-tests:
    name: unit-tests
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v6
      - name: Install bats
        run: sudo apt-get update && sudo apt-get install -y bats
      - run: make unit-tests

  integration-tests:
    name: integration-tests-${{ matrix.dokku-version }}
    runs-on: ubuntu-24.04
    strategy:
      matrix:
        dokku-version: [v0.34.8, master]
    env:
      DOKKU_TAG: ${{ matrix.dokku-version }}
    steps:
      - uses: actions/checkout@v6
      - run: sudo sysctl -w vm.max_map_count=262144
      - run: ./tests/setup-dokku.sh
      - run: |
          docker exec dokku-generic-test bash -c '
            apt-get update -qq && apt-get install -y -qq bats
            bats /var/lib/dokku/plugins/available/generic/tests/service_*.bats /var/lib/dokku/plugins/available/generic/tests/hook_*.bats /var/lib/dokku/plugins/available/generic/tests/link_networks.bats
          '
      - if: failure()
        uses: actions/upload-artifact@v7
        with:
          name: test-results-${{ matrix.dokku-version }}
          path: |
            tmp/test-results
            /tmp/dokku-debug
```

- [ ] **Step 2: smoke через act**

```bash
mkdir -p .github/workflows
make act-lint     # должен пройти
```

- [ ] **Step 3: commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: github actions ci.yml (lint + unit + integration matrix)"
```

---

## Task 2: `.github/workflows/tagged-release.yml`

**Files:**
- Create: `.github/workflows/tagged-release.yml`

- [ ] **Step 1: Файл**

```yaml
name: tagged-release

on:
  push:
    tags: ["*"]

jobs:
  release:
    name: release
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v6
      - name: Verify version matches plugin.toml
        run: |
          tag="${GITHUB_REF##*/}"
          tag_clean="${tag#v}"
          plugin_version=$(python3 -c "import tomllib; print(tomllib.load(open('plugin.toml','rb'))['plugin']['version'])")
          if [[ "$tag_clean" != "$plugin_version" ]]; then
            echo "Tag $tag (clean: $tag_clean) does not match plugin.toml version $plugin_version"
            exit 1
          fi
      - uses: softprops/action-gh-release@v3
        with:
          generate_release_notes: true
          make_latest: "true"
```

- [ ] **Step 2: commit**

```bash
git add .github/workflows/tagged-release.yml
git commit -m "ci: tagged-release workflow"
```

---

## Task 3: README — full version

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Полная версия README**

```markdown
# dokku-generic

[![CI](https://github.com/<owner>/dokku-generic/actions/workflows/ci.yml/badge.svg)](https://github.com/<owner>/dokku-generic/actions/workflows/ci.yml)

Universal Docker image service plugin for [Dokku](https://dokku.com).
Run **any Docker image** as a service: env vars, volumes, port exposure, app linking, and shell access — all through a familiar `dokku-redis`-style CLI.

- [Installation](#installation)
- [Quick start](#quick-start)
- [Examples](#examples)
  - [Atlassian MCP](#atlassian-mcp)
  - [Filesystem MCP](#filesystem-mcp)
  - [Postgres MCP](#postgres-mcp)
- [Command reference](#command-reference)
- [Differences from dokku-redis](#differences-from-dokku-redis)
- [Development](#development)

## Installation

```bash
sudo dokku plugin:install https://github.com/<owner>/dokku-generic.git generic
```

Requires Dokku ≥ v0.34 and Docker.

## Quick start

```bash
# create a service from any image
dokku generic:create cache redis:7-alpine --port 6379 --scheme redis

# link to your app — automatic CACHE_HOST / CACHE_PORT / CACHE_URL injection
dokku generic:create myapp
dokku generic:link cache myapp

# poke around
dokku generic:exec cache redis-cli ping
dokku generic:logs cache
dokku generic:enter cache

# expose to host
dokku generic:expose cache 16379:6379

# clean up
dokku generic:unlink cache myapp
dokku generic:destroy cache
```

## Examples

### Atlassian MCP

Bring an MCP server (Jira/Confluence) for use by your LLM-powered app:

```bash
dokku generic:create atlassian-mcp ghcr.io/sooperset/mcp-atlassian:latest \
  --port 9000 \
  --scheme http \
  --env JIRA_URL=https://mycompany.atlassian.net \
  --env JIRA_USERNAME=user@example.com \
  --env JIRA_API_TOKEN=xxxxxxxxxx \
  --env CONFLUENCE_URL=https://mycompany.atlassian.net/wiki \
  --env CONFLUENCE_USERNAME=user@example.com \
  --env CONFLUENCE_API_TOKEN=xxxxxxxxxx

dokku generic:link atlassian-mcp myapp
# myapp gets: ATLASSIAN_MCP_HOST, ATLASSIAN_MCP_PORT, ATLASSIAN_MCP_URL=http://...:9000
```

### Filesystem MCP

Bind-mount a host directory into an MCP filesystem server:

```bash
dokku generic:create fs-mcp mcp/filesystem:latest \
  --port 9001 \
  --scheme http \
  --mount /var/lib/myapp/uploads:/data \
  --cmd "/data"

dokku generic:link fs-mcp myapp
```

### Postgres MCP

Connect an existing dokku-postgres database to an MCP server (so an LLM in your app can query it):

```bash
DATABASE_URL=$(dokku postgres:info mydb --dsn)

dokku generic:create pg-mcp mcp/postgres:latest \
  --port 9002 \
  --scheme http \
  --env DATABASE_URL="$DATABASE_URL" \
  --docker-arg "--network=dokku-postgres-mydb"

dokku generic:link pg-mcp myapp
```

## Command reference

### Lifecycle

#### `generic:create <service> <image[:tag]> [flags]`

Create a new service. Flags:

| Flag | Description |
|---|---|
| `--port N` | Port inside container (for link variables and expose). |
| `--scheme STR` | URL scheme for `<PREFIX>_URL` (default: `tcp`). |
| `--env KEY=VAL` | Container env var (repeatable). |
| `--link-env KEY=VAL` | Extra env injected into linked apps (repeatable). |
| `--mount SPEC` | Mount: `/container/path` \| `/host:/container` \| `name:/container[:ro\|:rw]`. Repeatable. |
| `--expose H:C` | Expose port to host immediately. Repeatable. |
| `--cmd "..."` | CMD-override (placed after image). |
| `--entrypoint /bin/x` | Entrypoint-override. |
| `--docker-arg ARG` | Extra arg to docker run. Repeatable. |
| `--no-start` | Create state, don't start container. |

#### `generic:destroy <service> [-f|--force]`

Delete service: container, network, named volumes, state. Blocked if linked. Without `--force`, prompts to type the service name.

#### `generic:exists <service>`

Exit `0` if service exists, `1` otherwise.

#### `generic:list`

List all services with image and status.

#### `generic:info <service> [--<flag>]`

Print service info. Flags: `--image`, `--status`, `--port`, `--internal-ip`, `--links`, `--exposed-ports`. Without flag, prints all.

#### `generic:config <service>`

Print full configuration: env, link-env, mounts, exposed ports, port, scheme.

### Configuration

#### `generic:set <service> <flags>`

Same flags as `create` (except `--no-start`). Restarts the service.

#### `generic:unset <service> --<flag> KEY`

Remove a key. Flags: `--env`, `--link-env`, `--mount`, `--docker-arg`, `--expose`. Restarts the service.

#### `generic:upgrade <service> <new-image>`

Alias of `set --image`. Restarts.

#### `generic:clone <source> <new> [--copy-volumes] [override flags]`

Copy state to a new service. By default volumes are empty; with `--copy-volumes`, named-volume data is copied via busybox. Linked apps are not cloned.

#### `generic:rename <old> <new>`

Move state, copy volumes, recreate network, update all linked apps' `docker-options` and config vars.

### State control

```
generic:start <service>
generic:stop <service>
generic:restart <service>
generic:pause <service>          # toggles pause/unpause
```

### Access

```
generic:enter <service>                          # interactive bash (or sh fallback)
generic:exec <service> [-i] [-t] <cmd> [args]    # run command, exits with cmd's status
generic:logs <service> [-t] [-n N] [-f]
```

### Linking

```
generic:link <service> <app> [--alias PREFIX]    # injects <PREFIX>_HOST/PORT/URL + LINK_ENV
generic:unlink <service> <app>
generic:linked <service>                          # apps linked to service
generic:links <app>                               # services linked to app
generic:app-links <app>                           # alias of links
generic:promote <service> <app>                   # swap with primary alias
```

### Exposing ports

```
generic:expose <service> <host:container>        # starts ambassador
generic:unexpose <service> <host:container>      # removes ambassador for that port
```

## Differences from dokku-redis

| Aspect | dokku-redis | dokku-generic |
|---|---|---|
| Image | Fixed `redis` | Any image, passed at create |
| `connect` | Runs `redis-cli` | Use `exec <service> <command>` instead |
| `link` URL | `REDIS_URL=redis://...` (fixed) | `<SERVICE>_HOST/PORT/URL` (auto-prefix) + `LINK_ENV` |
| Backup/import/export | Yes (Redis dump) | No (out of scope; use `docker run --rm -v ... busybox tar -czf ...`) |
| Network | Single `dokku.network` | Per-service `dokku.generic.<svc>` |
| Linking mechanism | legacy `--link` | `--network=dokku.generic.<svc>` via docker-options |

## Development

```bash
# locally
make lint                     # shellcheck + shfmt
make unit-tests               # bats unit tests
make integration-tests        # spins up dokku in docker, runs bats

# CI workflows locally via act
make act-lint
make act-tests
make act
```

To release:
1. Bump version in `plugin.toml`.
2. `git tag vX.Y.Z && git push --tags`.
3. CI builds, tests, and publishes a GitHub Release.

Spec: [`docs/superpowers/specs/2026-05-06-dokku.generic.plugin-design.md`](docs/superpowers/specs/2026-05-06-dokku.generic.plugin-design.md).

## License

MIT — see [LICENSE.txt](LICENSE.txt).
```

- [ ] **Step 2: commit**

```bash
git add README.md
git commit -m "docs: full README with MCP examples and command reference"
```

---

## Task 4: Финальный smoke-test

- [ ] **Step 1: act lint**

```bash
make act-lint
```
Expected: green.

- [ ] **Step 2: act tests**

```bash
make act-tests
```
Expected: all bats tests pass on both v0.34.8 and master.

- [ ] **Step 3: Manual smoke с реальным MCP-образом**

```bash
./tests/setup-dokku.sh
docker exec dokku-generic-test dokku generic:create demo-fs mcp/filesystem:latest \
  --port 9001 --scheme http \
  --mount /tmp/data:/data --cmd "/data"
docker exec dokku-generic-test dokku apps:create demoapp
docker exec dokku-generic-test dokku generic:link demo-fs demoapp
docker exec dokku-generic-test dokku config:show demoapp | grep DEMO_FS
./tests/teardown-dokku.sh
```

- [ ] **Step 4: Тэг релиза**

```bash
# Bump version in plugin.toml from 0.1.0 to 0.1.0 if it's still 0.1.0; or 1.0.0 for first stable
git tag v0.1.0
git push --tags    # only when ready to publish
```

---

## Self-Review

Coverage:
- §6.2 GitHub Actions с матрицей версий — есть.
- §6.3 tagged-release — есть.
- §6.4 README с тремя MCP примерами + полным command reference — есть.
- README раздел "Differences from dokku-redis" — есть.

После завершения этого плана dokku-generic v0.1.0 готов к публикации.
