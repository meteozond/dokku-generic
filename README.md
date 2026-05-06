# dokku-generic

Universal Docker image service plugin for [Dokku](https://dokku.com).
Run **any Docker image** as a service: env vars, volumes, port exposure, app linking, shell access — all through a familiar `dokku-redis`-style CLI.

- [Installation](#installation)
- [Quick start](#quick-start)
- [Examples](#examples)
  - [Atlassian MCP](#atlassian-mcp)
  - [Filesystem MCP](#filesystem-mcp)
  - [Postgres MCP](#postgres-mcp)
- [Command reference](#command-reference)
- [Differences from dokku-redis](#differences-from-dokku-redis)
- [Development](#development)

## Status

In development. All 19 subcommands + 4 lifecycle hooks implemented and tested. Tagged-release workflow not yet wired (no `v0.1.0` published yet).

Spec: [`docs/superpowers/specs/2026-05-06-dokku-generic-plugin-design.md`](docs/superpowers/specs/2026-05-06-dokku-generic-plugin-design.md).
Implementation plans: [`docs/superpowers/plans/`](docs/superpowers/plans/).

## Installation

```bash
sudo dokku plugin:install https://github.com/<owner>/dokku-generic.git generic
```

Requires Dokku ≥ v0.34 and Docker.

## Quick start

```bash
# create a service from any image
dokku generic:create cache redis:7-alpine --port 6379 --scheme redis

# create an app and link the cache to it — automatic CACHE_HOST / CACHE_PORT / CACHE_URL injection
dokku apps:create myapp
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
| `--env KEY=VAL` | Container env var (repeatable, key must match `^[A-Z_][A-Z0-9_]*$`). |
| `--link-env KEY=VAL` | Extra env injected into linked apps (repeatable). |
| `--mount SPEC` | Mount: `/container/path` \| `/host:/container` \| `name:/container[:ro\|:rw]`. Repeatable. |
| `--expose H:C` | Expose port to host immediately via ambassador. Repeatable. |
| `--cmd "..."` | CMD-override (placed after image). |
| `--entrypoint /bin/x` | Entrypoint-override. |
| `--docker-arg ARG` | Extra arg to docker run (repeatable, whitespace preserved). |
| `--no-start` | Create state, don't start container. |

#### `generic:destroy <service> [-f|--force]`

Delete service: container, ambassadors, network, named volumes, state. Blocked if linked. Without `--force`, prompts to type the service name.

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

Same flags as `create` (except `--no-start`). Restarts the service if running.

#### `generic:unset <service> --<flag> KEY`

Remove a key. Flags: `--env`, `--link-env`, `--mount`, `--docker-arg`, `--expose`. Restarts if running.

#### `generic:upgrade <service> <new-image>`

Alias of `set --image`. Restarts if running.

#### `generic:clone <source> <new> [--copy-volumes] [override flags]`

Copy state to a new service. By default volumes are empty; with `--copy-volumes`, named-volume data is copied via busybox. Linked apps are not cloned.

#### `generic:rename <old> <new>`

Move state, copy volumes, recreate network, update all linked apps' `docker-options` and config vars.

### State control

```
generic:start <service>          # idempotent; recreates from state if no container
generic:stop <service>
generic:restart <service>
generic:pause <service>          # toggles pause/unpause
```

### Access

```
generic:enter <service>                          # interactive bash (or sh fallback)
generic:exec <service> [-i] [-t] <cmd> [args]    # run command, exit code propagates
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

When linking, the prefix defaults to the service name uppercased with `-`/`.` → `_` (e.g., `my-pg` → `MY_PG`). If that prefix is already in use on the app, the next available slot (`MY_PG2`, `MY_PG3`...) is taken.

### Exposing ports

```
generic:expose <service> <host:container>        # starts per-port ambassador, doesn't restart service
generic:unexpose <service> <host:container>      # removes ambassador for that port
```

Each exposed port runs its own ambassador container (`dokku/ambassador:0.8.2` by default), giving isolated TCP proxies that survive Docker restarts.

### Lifecycle hooks (auto-invoked by Dokku)

| Hook | Trigger | Action |
|---|---|---|
| `pre-start` | `dokku ps:start <app>` | Auto-starts any stopped linked services |
| `pre-delete` | `dokku apps:destroy <app>` | Removes app from `LINKS` of all services |
| `post-app-clone-setup` | `dokku apps:clone <old> <new>` | Re-links the new app to all services that were linked to old |
| `post-app-rename-setup` | `dokku apps:rename <old> <new>` | Updates `LINKS` files in-place |

`service-list` is also exposed for `dokku ls` integration.

## Differences from dokku-redis

| Aspect | dokku-redis | dokku-generic |
|---|---|---|
| Image | Fixed `redis` | Any image, passed at create time |
| `connect` | Runs `redis-cli` inside container | Use `exec <service> <command>` instead |
| `link` URL | `REDIS_URL=redis://...` (fixed) | `<PREFIX>_HOST/PORT/URL` (auto-prefix from service name) + custom `LINK_ENV` |
| Backup/import/export | Yes (Redis dump) | No (out of scope; use `docker run --rm -v <vol>:/data busybox tar -czf - /data > backup.tar.gz`) |
| Network model | Single `dokku.network` for all redises | Per-service network `dokku-generic-<svc>` (better isolation) |
| Linking mechanism | Legacy `--link` | `--network=dokku-generic-<svc>` via `docker-options` |
| Exposing | One ambassador for all ports | One ambassador **per port** (independent lifecycle) |
| Whitespace in args | N/A | `--docker-arg`/`--cmd` preserve whitespace via bash arrays |

## Development

```bash
# locally
make lint                     # shellcheck + shfmt
make unit-tests               # bats unit tests (66 tests)
make integration-tests        # spins up dokku in docker, runs bats (125 tests)

# CI workflows locally via act (requires brew install act)
make act-lint
make act-tests
make act
```

The CI matrix runs against Dokku `0.37.10` by default; extendable via `.github/workflows/ci.yml` matrix.

To bring up a Dokku container manually for ad-hoc poking:
```bash
./tests/setup-dokku.sh                                # boots dokku/dokku:0.37.10
docker exec -it dokku-generic-test bash               # enter the container
./tests/teardown-dokku.sh                             # stop & remove when done
```

The plugin source is mounted read-only at `/plugin-source` and copied to `/var/lib/dokku/plugins/available/generic` at startup.

## Known issues / backlog

See [`docs/superpowers/notes/known-issues.md`](docs/superpowers/notes/known-issues.md) for tracked minor issues, edge cases and refactor candidates.

## License

MIT — see [LICENSE.txt](LICENSE.txt).
