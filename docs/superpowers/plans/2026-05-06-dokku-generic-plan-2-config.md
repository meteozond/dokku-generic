# dokku-generic Plan 2 — Config (set / unset / upgrade)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development или superpowers:executing-plans.

**Goal:** Реализовать изменение конфигурации существующего сервиса теми же флагами, что и `create`. После завершения работают `dokku generic:set <svc> <флаги>`, `dokku generic:unset <svc> <флаги>`, `dokku generic:upgrade <svc> <new-image>`. Все три **рестартуют** сервис при успехе.

**Tech Stack:** bash, bats, Docker. Полагается на helpers и `subcommands/create` из Plan 1.

**References:**
- Spec §3.2 «Изменение конфигурации»
- Plan 1 — общая инфраструктура

**Prerequisite:** Plan 1 полностью реализован и протестирован.

---

## Task 1: Helper `service_restart_internal` — внутренний рестарт сервиса

**Goal:** Один раз стопаем + стартуем контейнер, читая параметры из state. Используется как из `set`/`unset`/`upgrade`, так и в Plan 3 (`subcommands/restart`).

**Files:**
- Modify: `functions`
- Modify: `tests/unit_helpers.bats`

- [ ] **Step 1: Failing test**

В `tests/unit_helpers.bats`:
```bash

@test "service_restart_internal recreates container with current state" {
  # этот test integration-уровня; запускаем внутри Dokku контейнера
  skip "integration test, run as part of bats integration suite"
}
```
(Это технически прокси-тест; реальная проверка — через `set` integration-tests.)

- [ ] **Step 2: Реализовать в `functions`**

```bash

# Stops the existing container (if any), and re-runs it with current state.
service_restart_internal() {
  local service="$1"
  local container network image
  container="$(service_container_name "$service")"
  network="$(service_network_name "$service")"
  image=$(<"$(service_root "$service")/IMAGE")

  # Stop+rm existing
  if "$DOCKER_BIN" container inspect "$container" >/dev/null 2>&1; then
    "$DOCKER_BIN" container stop -t "$PLUGIN_STOP_TIMEOUT" "$container" >/dev/null 2>&1 || true
    "$DOCKER_BIN" container rm "$container" >/dev/null 2>&1 || true
  fi

  # Ensure network exists
  "$DOCKER_BIN" network inspect "$network" >/dev/null 2>&1 \
    || "$DOCKER_BIN" network create "$network" >/dev/null

  # Pull image if missing
  if ! "$DOCKER_BIN" image inspect "$image" >/dev/null 2>&1; then
    "$DOCKER_BIN" image pull "$image" >/dev/null
  fi

  # Build args and run
  local run_args cmd_args
  run_args=$(build_run_args "$service")
  cmd_args=$(build_cmd_args "$service")

  # shellcheck disable=SC2086
  "$DOCKER_BIN" container run -d \
    --name "$container" \
    --hostname "$container" \
    --restart unless-stopped \
    --label dokku=service \
    --label "dokku.service=$PLUGIN_SERVICE" \
    --label "dokku.generic.service=$service" \
    --network "$network" \
    --network-alias "$service" \
    $run_args \
    "$image" \
    $cmd_args >/dev/null

  "$DOCKER_BIN" container inspect -f '{{.Id}}' "$container" > "$(service_root "$service")/ID"
}

# Returns 0 if the service container exists and is running.
service_is_running() {
  local container
  container="$(service_container_name "$1")"
  [[ "$("$DOCKER_BIN" container inspect -f '{{.State.Running}}' "$container" 2>/dev/null)" == "true" ]]
}
```

- [ ] **Step 3: Commit**

```bash
git add functions tests/unit_helpers.bats
git commit -m "feat: service_restart_internal and service_is_running helpers"
```

---

## Task 2: `subcommands/set` — изменение конфигурации

**Files:**
- Create: `subcommands/set`
- Create: `tests/service_set.bats`
- Modify: `commands` (добавить `generic:set`)

- [ ] **Step 1: Failing tests `tests/service_set.bats`**

```bash
#!/usr/bin/env bats

load test_helper

setup() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testset 2>/dev/null || true
  dokku "$PLUGIN_COMMAND_PREFIX:create" testset redis:7-alpine
}

teardown() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testset 2>/dev/null || true
}

@test "(generic:set --image) updates image and restarts" {
  run dokku "$PLUGIN_COMMAND_PREFIX:set" testset --image redis:7
  assert_success
  run cat "$PLUGIN_DATA_HOST_ROOT/testset/IMAGE"
  assert_output "redis:7"
  run docker container inspect -f '{{.Config.Image}}' "dokku.generic.testset"
  assert_output "redis:7"
}

@test "(generic:set --port) updates port" {
  dokku "$PLUGIN_COMMAND_PREFIX:set" testset --port 6380
  run cat "$PLUGIN_DATA_HOST_ROOT/testset/PORT"
  assert_output "6380"
}

@test "(generic:set --scheme) updates scheme" {
  dokku "$PLUGIN_COMMAND_PREFIX:set" testset --scheme redis
  run cat "$PLUGIN_DATA_HOST_ROOT/testset/SCHEME"
  assert_output "redis"
}

@test "(generic:set --env) adds and updates env vars" {
  dokku "$PLUGIN_COMMAND_PREFIX:set" testset --env FOO=bar
  run cat "$PLUGIN_DATA_HOST_ROOT/testset/ENV"
  assert_contains "$output" "FOO=bar"
  dokku "$PLUGIN_COMMAND_PREFIX:set" testset --env FOO=baz
  run cat "$PLUGIN_DATA_HOST_ROOT/testset/ENV"
  assert_contains "$output" "FOO=baz"
  assert_not_contains "$output" "FOO=bar"
}

@test "(generic:set --link-env) updates link-env" {
  dokku "$PLUGIN_COMMAND_PREFIX:set" testset --link-env DATABASE_URL=postgres://x
  run cat "$PLUGIN_DATA_HOST_ROOT/testset/LINK_ENV"
  assert_contains "$output" "DATABASE_URL=postgres://x"
}

@test "(generic:set --mount) appends mount" {
  dokku "$PLUGIN_COMMAND_PREFIX:set" testset --mount /data
  dokku "$PLUGIN_COMMAND_PREFIX:set" testset --mount /etc/conf
  run cat "$PLUGIN_DATA_HOST_ROOT/testset/MOUNTS"
  assert_contains "$output" "/data"
  assert_contains "$output" "/etc/conf"
}

@test "(generic:set --cmd) updates CMD" {
  dokku "$PLUGIN_COMMAND_PREFIX:set" testset --cmd "redis-server --bind 0.0.0.0"
  run cat "$PLUGIN_DATA_HOST_ROOT/testset/CMD"
  assert_output "redis-server --bind 0.0.0.0"
}

@test "(generic:set --entrypoint) updates ENTRYPOINT" {
  dokku "$PLUGIN_COMMAND_PREFIX:set" testset --entrypoint /bin/myinit
  run cat "$PLUGIN_DATA_HOST_ROOT/testset/ENTRYPOINT"
  assert_output "/bin/myinit"
}

@test "(generic:set --docker-arg) appends docker arg" {
  dokku "$PLUGIN_COMMAND_PREFIX:set" testset --docker-arg --user=1000
  run cat "$PLUGIN_DATA_HOST_ROOT/testset/DOCKER_ARGS"
  assert_contains "$output" "--user=1000"
}

@test "(generic:set) restarts container after change" {
  initial_id=$(docker container inspect -f '{{.Id}}' dokku.generic.testset)
  dokku "$PLUGIN_COMMAND_PREFIX:set" testset --env NEW=var
  new_id=$(docker container inspect -f '{{.Id}}' dokku.generic.testset)
  [[ "$initial_id" != "$new_id" ]] || flunk "expected container to be recreated"
}

@test "(generic:set) error when service missing" {
  run dokku "$PLUGIN_COMMAND_PREFIX:set" missing --image redis:7
  assert_failure
}

@test "(generic:set) accepts multiple flags in one call" {
  dokku "$PLUGIN_COMMAND_PREFIX:set" testset --image redis:7 --env FOO=bar --port 6379
  run cat "$PLUGIN_DATA_HOST_ROOT/testset/IMAGE"
  assert_output "redis:7"
  run cat "$PLUGIN_DATA_HOST_ROOT/testset/PORT"
  assert_output "6379"
}
```

- [ ] **Step 2: Создать `subcommands/set`**

```bash
#!/usr/bin/env bash
set -eo pipefail
[[ $DOKKU_TRACE ]] && set -x

PLUGIN_BASE_PATH="$(cd "$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")" && pwd)"
source "$PLUGIN_BASE_PATH/config"
source "$PLUGIN_BASE_PATH/common-functions"
source "$PLUGIN_BASE_PATH/functions"

shift
SERVICE=""
declare -a TO_SET_ENV=() TO_SET_LINK_ENV=() TO_ADD_MOUNT=() TO_ADD_DOCKER_ARG=()
NEW_IMAGE="" NEW_PORT="" NEW_SCHEME="" NEW_CMD="" NEW_ENTRYPOINT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --image)        NEW_IMAGE="$2"; shift 2 ;;
    --image=*)      NEW_IMAGE="${1#--image=}"; shift ;;
    --port)         NEW_PORT="$2"; shift 2 ;;
    --port=*)       NEW_PORT="${1#--port=}"; shift ;;
    --scheme)       NEW_SCHEME="$2"; shift 2 ;;
    --scheme=*)     NEW_SCHEME="${1#--scheme=}"; shift ;;
    --env)          TO_SET_ENV+=("$2"); shift 2 ;;
    --env=*)        TO_SET_ENV+=("${1#--env=}"); shift ;;
    --link-env)     TO_SET_LINK_ENV+=("$2"); shift 2 ;;
    --link-env=*)   TO_SET_LINK_ENV+=("${1#--link-env=}"); shift ;;
    --mount)        TO_ADD_MOUNT+=("$2"); shift 2 ;;
    --mount=*)      TO_ADD_MOUNT+=("${1#--mount=}"); shift ;;
    --cmd)          NEW_CMD="$2"; shift 2 ;;
    --cmd=*)        NEW_CMD="${1#--cmd=}"; shift ;;
    --entrypoint)   NEW_ENTRYPOINT="$2"; shift 2 ;;
    --entrypoint=*) NEW_ENTRYPOINT="${1#--entrypoint=}"; shift ;;
    --docker-arg)   TO_ADD_DOCKER_ARG+=("$2"); shift 2 ;;
    --docker-arg=*) TO_ADD_DOCKER_ARG+=("${1#--docker-arg=}"); shift ;;
    -*) dokku_log_fail "Unknown flag: $1" ;;
    *)
      [[ -n "$SERVICE" ]] && dokku_log_fail "Unexpected: $1"
      SERVICE="$1"; shift ;;
  esac
done

[[ -z "$SERVICE" ]] && dokku_log_fail "Please specify a valid name for the service"
verify_service_name "$SERVICE" || dokku_log_fail "Invalid service name: $SERVICE"
service_exists "$SERVICE" || dokku_log_fail "Service $SERVICE does not exist"

ROOT="$(service_root "$SERVICE")"

# Apply scalar fields
[[ -n "$NEW_IMAGE"      ]] && echo "$NEW_IMAGE"      > "$ROOT/IMAGE"
[[ -n "$NEW_PORT"       ]] && echo "$NEW_PORT"       > "$ROOT/PORT"
[[ -n "$NEW_SCHEME"     ]] && echo "$NEW_SCHEME"     > "$ROOT/SCHEME"
[[ -n "$NEW_CMD"        ]] && printf '%s' "$NEW_CMD"        > "$ROOT/CMD"
[[ -n "$NEW_ENTRYPOINT" ]] && printf '%s' "$NEW_ENTRYPOINT" > "$ROOT/ENTRYPOINT"

# Apply env / link-env
for pair in "${TO_SET_ENV[@]}"; do
  [[ "$pair" != *=* ]] && dokku_log_fail "Invalid --env: $pair"
  key="${pair%%=*}"; val="${pair#*=}"
  [[ "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]] || dokku_log_fail "Invalid --env key: $key"
  env_set "$ROOT/ENV" "$key" "$val"
done
for pair in "${TO_SET_LINK_ENV[@]}"; do
  [[ "$pair" != *=* ]] && dokku_log_fail "Invalid --link-env: $pair"
  key="${pair%%=*}"; val="${pair#*=}"
  [[ "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]] || dokku_log_fail "Invalid --link-env key: $key"
  env_set "$ROOT/LINK_ENV" "$key" "$val"
done

# Append mounts
for spec in "${TO_ADD_MOUNT[@]}"; do
  parse_mount_spec "$spec" >/dev/null || dokku_log_fail "Invalid --mount: $spec"
  echo "$spec" >> "$ROOT/MOUNTS"
done

# Append docker args
for da in "${TO_ADD_DOCKER_ARG[@]}"; do
  echo "$da" >> "$ROOT/DOCKER_ARGS"
done

dokku_log_info1 "Updated $SERVICE state"

# Restart if running (always restart per spec)
if service_is_running "$SERVICE"; then
  dokku_log_info1 "Restarting service to apply changes"
  service_restart_internal "$SERVICE"
fi
```

- [ ] **Step 3: Update `commands` dispatcher**

В case-листе `commands` добавить `generic:set` к списку обрабатываемых команд:
```bash
generic:create|generic:destroy|generic:exists|generic:list|generic:info|generic:config|generic:set)
```

- [ ] **Step 4: Make exec, run tests**

```bash
chmod +x subcommands/set
docker exec dokku-generic-test bats /var/lib/dokku/plugins/available/generic/tests/service_set.bats
```
Expected: 12 tests pass.

- [ ] **Step 5: Commit**

```bash
git add subcommands/set tests/service_set.bats commands
git commit -m "feat: subcommands/set with auto-restart"
```

---

## Task 3: `subcommands/unset`

**Goal:** Удалить отдельные ENV/LINK_ENV ключи, конкретные mounts, конкретные docker-args, конкретные exposed ports.

**Files:**
- Create: `subcommands/unset`
- Create: `tests/service_unset.bats`
- Modify: `commands`

- [ ] **Step 1: Failing tests**

```bash
#!/usr/bin/env bats

load test_helper

setup() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testunset 2>/dev/null || true
  dokku "$PLUGIN_COMMAND_PREFIX:create" testunset redis:7-alpine \
    --env FOO=bar --env BAZ=qux \
    --link-env DATABASE_URL=postgres://x \
    --mount /data --mount /etc/conf \
    --docker-arg --user=1000
}

teardown() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testunset 2>/dev/null || true
}

@test "(generic:unset --env) removes env key" {
  dokku "$PLUGIN_COMMAND_PREFIX:unset" testunset --env FOO
  run cat "$PLUGIN_DATA_HOST_ROOT/testunset/ENV"
  assert_not_contains "$output" "FOO"
  assert_contains "$output" "BAZ=qux"
}

@test "(generic:unset --link-env) removes link-env key" {
  dokku "$PLUGIN_COMMAND_PREFIX:unset" testunset --link-env DATABASE_URL
  run cat "$PLUGIN_DATA_HOST_ROOT/testunset/LINK_ENV" 2>/dev/null
  assert_not_contains "$output" "DATABASE_URL"
}

@test "(generic:unset --mount) removes mount entry" {
  dokku "$PLUGIN_COMMAND_PREFIX:unset" testunset --mount /data
  run cat "$PLUGIN_DATA_HOST_ROOT/testunset/MOUNTS"
  assert_not_contains "$output" "/data"
  assert_contains "$output" "/etc/conf"
}

@test "(generic:unset --docker-arg) removes specific docker arg" {
  dokku "$PLUGIN_COMMAND_PREFIX:unset" testunset --docker-arg --user=1000
  run cat "$PLUGIN_DATA_HOST_ROOT/testunset/DOCKER_ARGS" 2>/dev/null
  assert_not_contains "$output" "--user=1000"
}

@test "(generic:unset) restarts service" {
  initial_id=$(docker container inspect -f '{{.Id}}' dokku.generic.testunset)
  dokku "$PLUGIN_COMMAND_PREFIX:unset" testunset --env FOO
  new_id=$(docker container inspect -f '{{.Id}}' dokku.generic.testunset)
  [[ "$initial_id" != "$new_id" ]]
}

@test "(generic:unset) accepts multiple at once" {
  dokku "$PLUGIN_COMMAND_PREFIX:unset" testunset --env FOO --env BAZ --mount /data
  run cat "$PLUGIN_DATA_HOST_ROOT/testunset/ENV"
  assert_not_contains "$output" "FOO"
  assert_not_contains "$output" "BAZ"
}

@test "(generic:unset) is no-op for missing key" {
  run dokku "$PLUGIN_COMMAND_PREFIX:unset" testunset --env DOESNOTEXIST
  assert_success
}
```

- [ ] **Step 2: Создать `subcommands/unset`**

```bash
#!/usr/bin/env bash
set -eo pipefail
[[ $DOKKU_TRACE ]] && set -x

PLUGIN_BASE_PATH="$(cd "$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")" && pwd)"
source "$PLUGIN_BASE_PATH/config"
source "$PLUGIN_BASE_PATH/common-functions"
source "$PLUGIN_BASE_PATH/functions"

shift
SERVICE=""
declare -a UNSET_ENV=() UNSET_LINK_ENV=() UNSET_MOUNT=() UNSET_DOCKER_ARG=() UNSET_EXPOSE=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)          UNSET_ENV+=("$2"); shift 2 ;;
    --env=*)        UNSET_ENV+=("${1#--env=}"); shift ;;
    --link-env)     UNSET_LINK_ENV+=("$2"); shift 2 ;;
    --link-env=*)   UNSET_LINK_ENV+=("${1#--link-env=}"); shift ;;
    --mount)        UNSET_MOUNT+=("$2"); shift 2 ;;
    --mount=*)      UNSET_MOUNT+=("${1#--mount=}"); shift ;;
    --docker-arg)   UNSET_DOCKER_ARG+=("$2"); shift 2 ;;
    --docker-arg=*) UNSET_DOCKER_ARG+=("${1#--docker-arg=}"); shift ;;
    --expose)       UNSET_EXPOSE+=("$2"); shift 2 ;;
    --expose=*)     UNSET_EXPOSE+=("${1#--expose=}"); shift ;;
    -*) dokku_log_fail "Unknown flag: $1" ;;
    *)
      [[ -n "$SERVICE" ]] && dokku_log_fail "Unexpected: $1"
      SERVICE="$1"; shift ;;
  esac
done

[[ -z "$SERVICE" ]] && dokku_log_fail "Please specify a valid name for the service"
verify_service_name "$SERVICE" || dokku_log_fail "Invalid service name"
service_exists "$SERVICE" || dokku_log_fail "Service $SERVICE does not exist"

ROOT="$(service_root "$SERVICE")"

remove_line() {
  local file="$1" pattern="$2"
  [[ -f "$file" ]] || return 0
  local tmp
  tmp="$(mktemp "$(dirname "$file")/.unset.XXXXXX")"
  grep -vxF -- "$pattern" "$file" > "$tmp" || true
  mv "$tmp" "$file"
}

for k in "${UNSET_ENV[@]}";       do env_unset "$ROOT/ENV" "$k"; done
for k in "${UNSET_LINK_ENV[@]}";  do env_unset "$ROOT/LINK_ENV" "$k"; done
for spec in "${UNSET_MOUNT[@]}";       do remove_line "$ROOT/MOUNTS" "$spec"; done
for arg in "${UNSET_DOCKER_ARG[@]}";   do remove_line "$ROOT/DOCKER_ARGS" "$arg"; done
for ep in "${UNSET_EXPOSE[@]}";        do remove_line "$ROOT/EXPOSED_PORTS" "$ep"; done

dokku_log_info1 "Updated $SERVICE state"

if service_is_running "$SERVICE"; then
  dokku_log_info1 "Restarting service to apply changes"
  service_restart_internal "$SERVICE"
fi
```

- [ ] **Step 3: Update `commands`**

Добавить `generic:unset` в case-лист.

- [ ] **Step 4: Make exec & test**

```bash
chmod +x subcommands/unset
docker exec dokku-generic-test bats /var/lib/dokku/plugins/available/generic/tests/service_unset.bats
```

- [ ] **Step 5: Commit**

```bash
git add subcommands/unset tests/service_unset.bats commands
git commit -m "feat: subcommands/unset with line-removal helpers"
```

---

## Task 4: `subcommands/upgrade` (alias к set --image)

**Files:**
- Create: `subcommands/upgrade`
- Create: `tests/service_upgrade.bats`
- Modify: `commands`

- [ ] **Step 1: Failing tests**

```bash
#!/usr/bin/env bats

load test_helper

setup() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testupgrade 2>/dev/null || true
  dokku "$PLUGIN_COMMAND_PREFIX:create" testupgrade redis:7-alpine
}

teardown() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testupgrade 2>/dev/null || true
}

@test "(generic:upgrade) updates image and restarts" {
  run dokku "$PLUGIN_COMMAND_PREFIX:upgrade" testupgrade redis:7
  assert_success
  run cat "$PLUGIN_DATA_HOST_ROOT/testupgrade/IMAGE"
  assert_output "redis:7"
  run docker container inspect -f '{{.Config.Image}}' "dokku.generic.testupgrade"
  assert_output "redis:7"
}

@test "(generic:upgrade) error when service missing" {
  run dokku "$PLUGIN_COMMAND_PREFIX:upgrade" missing redis:7
  assert_failure
}

@test "(generic:upgrade) error when no image" {
  run dokku "$PLUGIN_COMMAND_PREFIX:upgrade" testupgrade
  assert_failure
}
```

- [ ] **Step 2: Создать `subcommands/upgrade`**

```bash
#!/usr/bin/env bash
set -eo pipefail
[[ $DOKKU_TRACE ]] && set -x

PLUGIN_BASE_PATH="$(cd "$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")" && pwd)"

shift
SERVICE="${1:-}"
IMAGE="${2:-}"

[[ -z "$SERVICE" ]] && { echo " !  Please specify a valid name for the service" >&2; exit 1; }
[[ -z "$IMAGE"   ]] && { echo " !  Please specify a docker image" >&2; exit 1; }

exec "$PLUGIN_BASE_PATH/subcommands/set" "generic:set" "$SERVICE" --image "$IMAGE"
```

- [ ] **Step 3: Update `commands`**

Добавить `generic:upgrade`.

- [ ] **Step 4: Make exec & test**

```bash
chmod +x subcommands/upgrade
docker exec dokku-generic-test bats /var/lib/dokku/plugins/available/generic/tests/service_upgrade.bats
```

- [ ] **Step 5: Commit**

```bash
git add subcommands/upgrade tests/service_upgrade.bats commands
git commit -m "feat: subcommands/upgrade as alias to set --image"
```

---

## Self-Review

1. Покрытие spec'и §3.2: `set`, `unset`, `upgrade` — есть.
2. Все рестартуют сервис при running — реализовано через `service_is_running` + `service_restart_internal`.
3. Multi-flag в одном вызове `set` — поддерживается, рестарт один в конце.
4. Если рестарт упал — state в новом виде, exit от `service_restart_internal`. Достаточно ли понятное сообщение? Проверить вручную в smoke.
