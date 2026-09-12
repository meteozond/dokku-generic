# Changelog

All notable changes to `dokku-generic` are documented in this file.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-09-12

Initial release.

### Added

**Service lifecycle**
- `generic:create <service> <image[:tag]> [flags]` — create a service from any Docker image. Flags: `--port`, `--scheme`, `--env`, `--link-env`, `--mount` (bind/named/auto), `--expose`, `--cmd`, `--entrypoint`, `--docker-arg`, `--no-start`.
- `generic:destroy <service> [-f|--force]` — remove service (container, ambassadors, network, named volumes, state). Blocks if linked. Prompts for service name without `--force`; also honours `dokku --force` (`DOKKU_APPS_FORCE_DELETE`).
- `generic:exists <service>` — exit 0/1 check.
- `generic:list` — table of services with image and status.
- `generic:info <service> [--<flag>]` — full report or single field (`--image`, `--status`, `--port`, `--internal-ip`, `--links`, `--exposed-ports`).
- `generic:config <service>` — env, link-env, mounts, exposed ports, port, scheme.

**Configuration**
- `generic:set <service> <flags>` — mirrors `create` flags (minus `--no-start`), auto-restarts if running.
- `generic:unset <service> --<flag> KEY` — remove specific `--env` / `--link-env` / `--mount` / `--docker-arg` / `--expose`.
- `generic:upgrade <service> <new-image>` — alias for `set --image`.
- `generic:clone <source> <new> [--copy-volumes] [override flags]` — copy state; optionally copy named-volume data via a busybox helper.
- `generic:rename <old> <new>` — full move: state, volumes, network, linked-app docker-options and config.

**Container control**
- `generic:start` (idempotent + recreates from state if no container), `generic:stop`, `generic:restart`, `generic:pause` (toggles).

**Access**
- `generic:enter` — interactive shell (bash → sh fallback, TTY-aware).
- `generic:exec [-i] [-t] <cmd> [args...]` — arbitrary command, exit code propagates.
- `generic:logs [-t] [-n N] [-f]`.

**Linking with Dokku apps**
- `generic:link <service> <app> [--alias PREFIX]` — auto-injects `<PREFIX>_HOST/PORT/URL` + `LINK_ENV` variables into app config; adds per-service network via `docker-options`.
- `generic:unlink <service> <app>` — reverse.
- `generic:linked <service>`, `generic:links <app>`, `generic:app-links <app>` (alias of `links`).
- `generic:promote <service> <app>` — swap primary alias when multiple services share a prefix.
- `--link-env` values support `%h` / `%p` / `%s` placeholders (host / port / scheme) interpolated at link time; `%%` escapes a literal `%`.
- Automatic prefix collision resolution: `<PREFIX>2`, `<PREFIX>3`, … when the first slot is taken.

**Exposing ports**
- `generic:expose <service> <host:container>` — starts a per-port ambassador container (`dokku/ambassador:0.8.2`) without restarting the service.
- `generic:unexpose <service> <host:container>` — tears down that ambassador.

**Lifecycle hooks (auto-invoked by Dokku core)**
- `pre-start <app>` — auto-starts stopped linked services.
- `pre-delete <app>` — removes app from `LINKS` of all services.
- `post-app-clone-setup <old> <new>` — re-links the new app to all services linked to old.
- `post-app-rename-setup <old> <new>` — rewrites app name in-place in every `LINKS` file.
- `service-list` — exposes services to `dokku ls`.

**Environment overrides**
- `PLUGIN_AMBASSADOR_IMAGE` (default `dokku/ambassador:0.8.2`)
- `PLUGIN_BUSYBOX_IMAGE` (default `busybox:1.36`) — used by `clone --copy-volumes` and `rename` for volume data copy.
- `PLUGIN_STOP_TIMEOUT` (default `10`)
- `PLUGIN_RESTART_POLICY` (default `unless-stopped`)
- `DOCKER_BIN` (default `docker`)
- `DOKKU_TRACE` — when set, every plugin command prints its own commands (`set -x`).

**Custom `docker run` args escape hatch**
- `--docker-arg ARG` (repeatable) — passed verbatim to `docker run`. Whitespace preserved via global bash arrays (`_DOCKER_RUN_ARGS`).
- If `--docker-arg` supplies `--net=host` / `--network=container:...`, the per-service `--network`/`--network-alias` is skipped (docker rejects combining them).

**CI**
- GitHub Actions workflow (`.github/workflows/ci.yml`): three jobs — `lint`, `unit-tests`, `integration-tests` (matrix over Dokku versions).
- Compatible with local [`act`](https://github.com/nektos/act): `make act-lint`, `make act-tests`.
- Bash linting stack: [shellcheck](https://www.shellcheck.net/) (semantics) + [shfmt](https://github.com/mvdan/sh) (format) + [bashate](https://opendev.org/openstack/bashate) (style). All three are `make lint`.
- Integration test harness: `tests/setup-dokku.sh` boots `dokku/dokku` (default `0.37.10`) in Docker with the plugin mounted read-only.

### Changed

- **Breaking (pre-release): Container and network names now use dot separator.** `dokku-generic-<svc>` → `dokku.generic.<svc>`. Matches convention set by `dokku-redis`, `dokku-postgres`. Volume names already used dot-separator; unchanged.
- Dispatcher (`commands`) uses `generic:*` glob instead of a hard-coded list of subcommands. Adding a new subcommand is now just dropping an executable into `subcommands/`.
- `subcommands/set` applies all flags to state first, restarts container **once** at the end (not per-flag).

### Fixed

- Whitespace in `--docker-arg` / `--cmd` values is preserved. `build_run_args` / `build_cmd_args` populate global bash arrays instead of returning space-separated strings that got word-split.
- Rename correctly rewrites `<OLD_ALIAS>_HOST/PORT/URL` config keys on every linked app; also rewrites `LINK_ENV` values that reference the old container DNS. Uses double-quote stripping (`"`) as `dokku config:export --format=envfile` produces double-quoted values.
- `create`'s `cleanup_on_fail` trap now removes the container in addition to network and state — avoids orphan container blocking a subsequent `create` with the same name.
- `parse_mount_spec` accepts `:RO` / `:RW` mode suffixes case-insensitively; previously uppercase silently ended up appended to the target path.
- `service_alternative_alias` uses `i=$((i+1))` instead of `((i++))` — the latter returns pre-increment value and would trip `set -e` if that value were zero.
- Config file (`config`) drops a dead source guard copied from another codebase.

### Documentation

- Full `README.md` with quick-start, three MCP-server examples (Atlassian, filesystem, Postgres), command reference, environment overrides, differences from `dokku-redis`, development section.
- `INSTALL.md` — installation without `dokku plugin:install <git>`: rsync, `scp -r`, `git archive`, `tar` pipe, `docker cp`; includes zsh/bash equivalents for excluding dotfiles.

[Unreleased]: https://github.com/meteozond/dokku-generic/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/meteozond/dokku-generic/releases/tag/v1.0.0
