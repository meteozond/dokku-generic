# dokku-generic

Universal [Dokku](https://dokku.com) plugin for any Docker image.

Run any Docker image as a Dokku-managed service — env vars, volumes, port exposure, app linking, shell access — through a familiar `dokku-redis`-style CLI.

- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Examples](#examples)
  - [Atlassian MCP](#atlassian-mcp)
  - [Filesystem MCP](#filesystem-mcp)
  - [Postgres MCP](#postgres-mcp)
- [Commands](#commands)
- [Command reference](#command-reference)
- [Environment overrides](#environment-overrides)
- [Differences from dokku-redis](#differences-from-dokku-redis)
- [Development](#development)

## Requirements

- Dokku ≥ v0.34
- Docker

## Installation

```bash
sudo dokku plugin:install https://github.com/meteozond/dokku-generic.git generic
```

For installation **without git** (rsync/scp/tarball/`docker cp`), see [docs/install-without-git.md](docs/install-without-git.md).

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

# expose to host (via per-port ambassador, doesn't restart service)
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
# myapp gets in its config:
#   ATLASSIAN_MCP_HOST=dokku-generic-atlassian-mcp
#   ATLASSIAN_MCP_PORT=9000
#   ATLASSIAN_MCP_URL=http://dokku-generic-atlassian-mcp:9000
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
# myapp gets in its config:
#   FS_MCP_HOST=dokku-generic-fs-mcp
#   FS_MCP_PORT=9001
#   FS_MCP_URL=http://dokku-generic-fs-mcp:9001
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
# myapp gets in its config:
#   PG_MCP_HOST=dokku-generic-pg-mcp
#   PG_MCP_PORT=9002
#   PG_MCP_URL=http://dokku-generic-pg-mcp:9002
```

## Commands

```
generic:app-links <app>                                    # alias of generic:links
generic:clone <source> <new> [--copy-volumes] [flags...]   # copy state to a new service
generic:config <service>                                   # print env, link-env, mounts, exposed ports, port, scheme
generic:create <service> <image[:tag]> [flags...]          # create a new service from a Docker image
generic:destroy <service> [-f|--force]                     # delete service: container, ambassadors, network, volumes, state
generic:enter <service>                                    # interactive shell (bash with sh fallback)
generic:exec <service> [-i] [-t] <cmd> [args...]           # run command inside container, exit code propagates
generic:exists <service>                                   # exit 0 if service exists, 1 otherwise
generic:expose <service> <host:container>                  # open port on host via per-port ambassador (no service restart)
generic:help                                               # plugin overview
generic:info <service> [--<flag>]                          # service info; flags: --image|--status|--port|--internal-ip|--links|--exposed-ports
generic:link <service> <app> [--alias PREFIX]              # link service to app; injects <PREFIX>_HOST/PORT/URL + LINK_ENV
generic:linked <service>                                   # list apps linked to a service
generic:links <app>                                        # list services linked to an app
generic:list                                               # list all services with image and status
generic:logs <service> [-t] [-n N] [-f]                    # show container logs
generic:pause <service>                                    # toggle pause/unpause
generic:promote <service> <app>                            # swap with primary alias when multiple services share prefix
generic:rename <old> <new>                                 # rename service: state, volumes, network, linked-app config
generic:restart <service>                                  # recreate container with current state
generic:set <service> <flags...>                           # update config (same flags as create); auto-restarts if running
generic:start <service>                                    # start stopped service; idempotent; recreates from state if no container
generic:stop <service>                                     # stop running service
generic:unexpose <service> <host:container>                # remove port mapping; tears down its ambassador
generic:unlink <service> <app>                             # disconnect service from app
generic:unset <service> --<flag> KEY                       # remove env/link-env/mount/docker-arg/expose; auto-restarts if running
generic:upgrade <service> <new-image[:tag]>                # alias of set --image
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

#### What variables show up in the linked app

After `dokku generic:link <service> <app>`, the app's config (visible via `dokku config:show <app>`) gains:

| Variable | Always set? | Value |
|---|---|---|
| `<PREFIX>_HOST` | yes | DNS name of service container, e.g. `dokku-generic-<svc>` |
| `<PREFIX>_PORT` | only if service has `--port` | port number |
| `<PREFIX>_URL` | only if service has `--port` | `<scheme>://<PREFIX>_HOST:<PREFIX>_PORT` (scheme from `--scheme`, default `tcp`) |
| every `--link-env KEY=VAL` | yes | as-is (overrides above on key collision) |

`<PREFIX>` is the service name uppercased, with `-` and `.` replaced by `_` (e.g., `my-pg` → `MY_PG`). Custom prefix via `--alias`. On collision (existing `<PREFIX>_URL`), the next free slot is taken (`MY_PG2`, `MY_PG3`...).

Example:
```bash
dokku generic:create cache redis:7-alpine \
  --port 6379 --scheme redis \
  --link-env CACHE_PASSWORD=secret
dokku generic:link cache myapp

# now in myapp:
dokku config:show myapp
# CACHE_HOST=dokku-generic-cache
# CACHE_PORT=6379
# CACHE_URL=redis://dokku-generic-cache:6379
# CACHE_PASSWORD=secret
```

In the app, your code reads these env vars to connect:
```python
redis.from_url(os.environ["CACHE_URL"], password=os.environ["CACHE_PASSWORD"])
```

The app container is also placed on the service's Docker network (via `dokku docker-options:add ... --network=dokku-generic-<svc>`), so the DNS name actually resolves at runtime.

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

## Environment overrides

Plugin behavior tunable via environment variables (override before invoking dokku):

| Variable | Default | Effect |
|---|---|---|
| `PLUGIN_AMBASSADOR_IMAGE` | `dokku/ambassador:0.8.2` | Image used for `expose` ambassadors. Override for airgapped installs. |
| `PLUGIN_BUSYBOX_IMAGE` | `busybox:1.36` | Image used by `clone --copy-volumes` and `rename` for volume data copy. |
| `PLUGIN_STOP_TIMEOUT` | `10` | Graceful stop timeout in seconds for `stop`/`restart`. |
| `DOCKER_BIN` | `docker` | Docker CLI binary path (override for podman, custom builds, etc). |
| `DOKKU_TRACE` | unset | If set to any value, every command in plugin scripts is printed before execution (`set -x`). Useful for debugging hooks. |

Apply for one command:
```bash
DOKKU_TRACE=1 dokku generic:create pg postgres:15
```

Apply persistently for the dokku user (e.g. on Dokku host):
```bash
echo 'export PLUGIN_AMBASSADOR_IMAGE=registry.internal/ambassador:1.0' >> /home/dokku/.bashrc
```

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

## Status

In development. All 19 subcommands + 4 lifecycle hooks implemented and tested. Tagged-release workflow not yet wired (no `v0.1.0` published yet).

Spec: [`docs/superpowers/specs/2026-05-06-dokku-generic-plugin-design.md`](docs/superpowers/specs/2026-05-06-dokku-generic-plugin-design.md).
Implementation plans: [`docs/superpowers/plans/`](docs/superpowers/plans/).

## Known issues / backlog

See [`docs/superpowers/notes/known-issues.md`](docs/superpowers/notes/known-issues.md) for tracked minor issues, edge cases and refactor candidates.

## License

MIT — see [LICENSE.txt](LICENSE.txt).
