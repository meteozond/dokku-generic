# dokku-generic Plan 3 — Runtime (start / stop / restart / pause / enter / exec / logs)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development или superpowers:executing-plans.

**Goal:** Реализовать управление состоянием контейнера и доступ внутрь.

**Prerequisite:** Plans 1 + 2.

---

## Task 1: `subcommands/start`

**Files:**
- Create: `subcommands/start`
- Create: `tests/service_start.bats`
- Modify: `commands`

- [ ] **Step 1: Tests**

```bash
#!/usr/bin/env bats

load test_helper

setup() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" teststart 2>/dev/null || true
}

teardown() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" teststart 2>/dev/null || true
}

@test "(generic:start) starts a stopped service" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" teststart redis:7-alpine
  docker container stop dokku.generic.teststart
  run dokku "$PLUGIN_COMMAND_PREFIX:start" teststart
  assert_success
  run docker container inspect -f '{{.State.Status}}' dokku.generic.teststart
  assert_output "running"
}

@test "(generic:start) is no-op when running" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" teststart redis:7-alpine
  run dokku "$PLUGIN_COMMAND_PREFIX:start" teststart
  assert_success
  assert_contains "$output" "already running"
}

@test "(generic:start) recreates from state when no container" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" teststart redis:7-alpine --no-start
  run dokku "$PLUGIN_COMMAND_PREFIX:start" teststart
  assert_success
  run docker container inspect -f '{{.State.Status}}' dokku.generic.teststart
  assert_output "running"
}

@test "(generic:start) error when missing" {
  run dokku "$PLUGIN_COMMAND_PREFIX:start" missing
  assert_failure
}
```

- [ ] **Step 2: Реализация**

```bash
#!/usr/bin/env bash
set -eo pipefail
[[ $DOKKU_TRACE ]] && set -x

PLUGIN_BASE_PATH="$(cd "$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")" && pwd)"
source "$PLUGIN_BASE_PATH/config"
source "$PLUGIN_BASE_PATH/common-functions"
source "$PLUGIN_BASE_PATH/functions"

shift
SERVICE="${1:-}"
[[ -z "$SERVICE" ]] && dokku_log_fail "Please specify a valid name for the service"
verify_service_name "$SERVICE" || dokku_log_fail "Invalid service name"
service_exists "$SERVICE" || dokku_log_fail "Service $SERVICE does not exist"

CONTAINER="$(service_container_name "$SERVICE")"

if service_is_running "$SERVICE"; then
  dokku_log_info1 "Service $SERVICE already running"
  exit 0
fi

if "$DOCKER_BIN" container inspect "$CONTAINER" >/dev/null 2>&1; then
  "$DOCKER_BIN" container start "$CONTAINER" >/dev/null
else
  service_restart_internal "$SERVICE"
fi
dokku_log_info2 "Started $SERVICE"
```

- [ ] **Step 3: Add to `commands`, make exec, test, commit**

```bash
chmod +x subcommands/start
# add generic:start to commands case
docker exec dokku-generic-test bats /var/lib/dokku/plugins/available/generic/tests/service_start.bats
git add subcommands/start tests/service_start.bats commands
git commit -m "feat: subcommands/start (idempotent + recreate from state)"
```

---

## Task 2: `subcommands/stop`

**Files:**
- Create: `subcommands/stop`
- Create: `tests/service_stop.bats`

- [ ] **Step 1: Tests**

```bash
#!/usr/bin/env bats

load test_helper

setup() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" teststop 2>/dev/null || true
  dokku "$PLUGIN_COMMAND_PREFIX:create" teststop redis:7-alpine
}

teardown() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" teststop 2>/dev/null || true
}

@test "(generic:stop) stops a running service" {
  run dokku "$PLUGIN_COMMAND_PREFIX:stop" teststop
  assert_success
  run docker container inspect -f '{{.State.Status}}' dokku.generic.teststop
  assert_output "exited"
}

@test "(generic:stop) is no-op when stopped" {
  docker container stop dokku.generic.teststop
  run dokku "$PLUGIN_COMMAND_PREFIX:stop" teststop
  assert_success
}
```

- [ ] **Step 2: Реализация**

```bash
#!/usr/bin/env bash
set -eo pipefail
[[ $DOKKU_TRACE ]] && set -x

PLUGIN_BASE_PATH="$(cd "$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")" && pwd)"
source "$PLUGIN_BASE_PATH/config"
source "$PLUGIN_BASE_PATH/common-functions"

shift
SERVICE="${1:-}"
[[ -z "$SERVICE" ]] && dokku_log_fail "Please specify a valid name for the service"
verify_service_name "$SERVICE" || dokku_log_fail "Invalid service name"
service_exists "$SERVICE" || dokku_log_fail "Service $SERVICE does not exist"

CONTAINER="$(service_container_name "$SERVICE")"

if "$DOCKER_BIN" container inspect "$CONTAINER" >/dev/null 2>&1; then
  "$DOCKER_BIN" container stop -t "$PLUGIN_STOP_TIMEOUT" "$CONTAINER" >/dev/null 2>&1 || true
fi
dokku_log_info2 "Stopped $SERVICE"
```

- [ ] **Step 3: commit**

```bash
chmod +x subcommands/stop
# add generic:stop to commands
docker exec dokku-generic-test bats /var/lib/dokku/plugins/available/generic/tests/service_stop.bats
git add subcommands/stop tests/service_stop.bats commands
git commit -m "feat: subcommands/stop"
```

---

## Task 3: `subcommands/restart`

**Files:**
- Create: `subcommands/restart`
- Create: `tests/service_restart.bats`

- [ ] **Step 1: Tests**

```bash
#!/usr/bin/env bats

load test_helper

setup() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testrestart 2>/dev/null || true
  dokku "$PLUGIN_COMMAND_PREFIX:create" testrestart redis:7-alpine
}

teardown() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testrestart 2>/dev/null || true
}

@test "(generic:restart) recreates container with current state" {
  initial_id=$(docker container inspect -f '{{.Id}}' dokku.generic.testrestart)
  run dokku "$PLUGIN_COMMAND_PREFIX:restart" testrestart
  assert_success
  new_id=$(docker container inspect -f '{{.Id}}' dokku.generic.testrestart)
  [[ "$initial_id" != "$new_id" ]]
}

@test "(generic:restart) error when missing" {
  run dokku "$PLUGIN_COMMAND_PREFIX:restart" missing
  assert_failure
}
```

- [ ] **Step 2: Реализация**

```bash
#!/usr/bin/env bash
set -eo pipefail
[[ $DOKKU_TRACE ]] && set -x

PLUGIN_BASE_PATH="$(cd "$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")" && pwd)"
source "$PLUGIN_BASE_PATH/config"
source "$PLUGIN_BASE_PATH/common-functions"
source "$PLUGIN_BASE_PATH/functions"

shift
SERVICE="${1:-}"
[[ -z "$SERVICE" ]] && dokku_log_fail "Please specify a valid name for the service"
verify_service_name "$SERVICE" || dokku_log_fail "Invalid service name"
service_exists "$SERVICE" || dokku_log_fail "Service $SERVICE does not exist"

service_restart_internal "$SERVICE"
dokku_log_info2 "Restarted $SERVICE"
```

- [ ] **Step 3: commit**

```bash
chmod +x subcommands/restart
docker exec dokku-generic-test bats /var/lib/dokku/plugins/available/generic/tests/service_restart.bats
git add subcommands/restart tests/service_restart.bats commands
git commit -m "feat: subcommands/restart"
```

---

## Task 4: `subcommands/pause`

**Files:**
- Create: `subcommands/pause`
- Create: `tests/service_pause.bats`

- [ ] **Step 1: Tests**

```bash
#!/usr/bin/env bats

load test_helper

setup() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testpause 2>/dev/null || true
  dokku "$PLUGIN_COMMAND_PREFIX:create" testpause redis:7-alpine
}

teardown() {
  docker container unpause dokku.generic.testpause 2>/dev/null || true
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testpause 2>/dev/null || true
}

@test "(generic:pause) pauses running container" {
  run dokku "$PLUGIN_COMMAND_PREFIX:pause" testpause
  assert_success
  run docker container inspect -f '{{.State.Status}}' dokku.generic.testpause
  assert_output "paused"
}

@test "(generic:pause) unpauses paused container (toggle)" {
  dokku "$PLUGIN_COMMAND_PREFIX:pause" testpause
  run dokku "$PLUGIN_COMMAND_PREFIX:pause" testpause
  assert_success
  run docker container inspect -f '{{.State.Status}}' dokku.generic.testpause
  assert_output "running"
}
```

- [ ] **Step 2: Реализация**

```bash
#!/usr/bin/env bash
set -eo pipefail
[[ $DOKKU_TRACE ]] && set -x

PLUGIN_BASE_PATH="$(cd "$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")" && pwd)"
source "$PLUGIN_BASE_PATH/config"
source "$PLUGIN_BASE_PATH/common-functions"

shift
SERVICE="${1:-}"
[[ -z "$SERVICE" ]] && dokku_log_fail "Please specify a valid name for the service"
verify_service_name "$SERVICE" || dokku_log_fail "Invalid service name"
service_exists "$SERVICE" || dokku_log_fail "Service $SERVICE does not exist"

CONTAINER="$(service_container_name "$SERVICE")"
status=$("$DOCKER_BIN" container inspect -f '{{.State.Status}}' "$CONTAINER" 2>/dev/null || echo "")

case "$status" in
  paused)  "$DOCKER_BIN" container unpause "$CONTAINER" >/dev/null; dokku_log_info2 "Unpaused $SERVICE" ;;
  running) "$DOCKER_BIN" container pause "$CONTAINER" >/dev/null; dokku_log_info2 "Paused $SERVICE" ;;
  *)       dokku_log_fail "Service $SERVICE is not running (status: $status)" ;;
esac
```

- [ ] **Step 3: commit**

```bash
chmod +x subcommands/pause
docker exec dokku-generic-test bats /var/lib/dokku/plugins/available/generic/tests/service_pause.bats
git add subcommands/pause tests/service_pause.bats commands
git commit -m "feat: subcommands/pause as toggle"
```

---

## Task 5: `subcommands/enter`

**Goal:** интерактивный shell внутри контейнера. Bash → sh fallback.

**Files:**
- Create: `subcommands/enter`
- Create: `tests/service_enter.bats`

- [ ] **Step 1: Tests** (non-interactive emulation через `echo | docker exec -i`)

```bash
#!/usr/bin/env bats

load test_helper

setup() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testenter 2>/dev/null || true
  dokku "$PLUGIN_COMMAND_PREFIX:create" testenter redis:7-alpine
}

teardown() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testenter 2>/dev/null || true
}

@test "(generic:enter) drops into shell (sh fallback for alpine)" {
  run bash -c "echo 'echo hello-from-shell; exit' | dokku '$PLUGIN_COMMAND_PREFIX:enter' testenter"
  assert_success
  assert_contains "$output" "hello-from-shell"
}

@test "(generic:enter) error when not running" {
  docker container stop dokku.generic.testenter
  run dokku "$PLUGIN_COMMAND_PREFIX:enter" testenter
  assert_failure
}
```

- [ ] **Step 2: Реализация**

```bash
#!/usr/bin/env bash
set -eo pipefail
[[ $DOKKU_TRACE ]] && set -x

PLUGIN_BASE_PATH="$(cd "$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")" && pwd)"
source "$PLUGIN_BASE_PATH/config"
source "$PLUGIN_BASE_PATH/common-functions"
source "$PLUGIN_BASE_PATH/functions"

shift
SERVICE="${1:-}"
[[ -z "$SERVICE" ]] && dokku_log_fail "Please specify a valid name for the service"
verify_service_name "$SERVICE" || dokku_log_fail "Invalid service name"
service_exists "$SERVICE" || dokku_log_fail "Service $SERVICE does not exist"
service_is_running "$SERVICE" || dokku_log_fail "Service $SERVICE is not running"

CONTAINER="$(service_container_name "$SERVICE")"

# Try bash first, fall back to sh
if "$DOCKER_BIN" exec "$CONTAINER" sh -c 'command -v bash' >/dev/null 2>&1; then
  exec "$DOCKER_BIN" exec -it "$CONTAINER" bash
else
  exec "$DOCKER_BIN" exec -it "$CONTAINER" sh
fi
```

- [ ] **Step 3: commit**

```bash
chmod +x subcommands/enter
docker exec dokku-generic-test bats /var/lib/dokku/plugins/available/generic/tests/service_enter.bats
git add subcommands/enter tests/service_enter.bats commands
git commit -m "feat: subcommands/enter (bash with sh fallback)"
```

---

## Task 6: `subcommands/exec`

**Files:**
- Create: `subcommands/exec`
- Create: `tests/service_exec.bats`

- [ ] **Step 1: Tests**

```bash
#!/usr/bin/env bats

load test_helper

setup() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testexec 2>/dev/null || true
  dokku "$PLUGIN_COMMAND_PREFIX:create" testexec redis:7-alpine
}

teardown() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testexec 2>/dev/null || true
}

@test "(generic:exec) runs command and captures output" {
  run dokku "$PLUGIN_COMMAND_PREFIX:exec" testexec redis-cli ping
  assert_success
  assert_output "PONG"
}

@test "(generic:exec) propagates non-zero exit" {
  run dokku "$PLUGIN_COMMAND_PREFIX:exec" testexec false
  [[ "$status" -ne 0 ]]
}

@test "(generic:exec) error when not running" {
  docker container stop dokku.generic.testexec
  run dokku "$PLUGIN_COMMAND_PREFIX:exec" testexec echo hi
  assert_failure
}
```

- [ ] **Step 2: Реализация**

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
TTY_FLAG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i) TTY_FLAG="$TTY_FLAG -i"; shift ;;
    -t) TTY_FLAG="$TTY_FLAG -t"; shift ;;
    -it|-ti) TTY_FLAG="$TTY_FLAG -it"; shift ;;
    *)
      if [[ -z "$SERVICE" ]]; then
        SERVICE="$1"; shift
      else
        break
      fi
      ;;
  esac
done

[[ -z "$SERVICE" ]] && dokku_log_fail "Please specify a valid name for the service"
[[ $# -eq 0 ]] && dokku_log_fail "Please specify a command to exec"
verify_service_name "$SERVICE" || dokku_log_fail "Invalid service name"
service_exists "$SERVICE" || dokku_log_fail "Service $SERVICE does not exist"
service_is_running "$SERVICE" || dokku_log_fail "Service $SERVICE is not running"

CONTAINER="$(service_container_name "$SERVICE")"

# shellcheck disable=SC2086
exec "$DOCKER_BIN" exec $TTY_FLAG "$CONTAINER" "$@"
```

- [ ] **Step 3: commit**

```bash
chmod +x subcommands/exec
docker exec dokku-generic-test bats /var/lib/dokku/plugins/available/generic/tests/service_exec.bats
git add subcommands/exec tests/service_exec.bats commands
git commit -m "feat: subcommands/exec with -i/-t flags"
```

---

## Task 7: `subcommands/logs`

**Files:**
- Create: `subcommands/logs`
- Create: `tests/service_logs.bats`

- [ ] **Step 1: Tests**

```bash
#!/usr/bin/env bats

load test_helper

setup() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testlogs 2>/dev/null || true
  dokku "$PLUGIN_COMMAND_PREFIX:create" testlogs redis:7-alpine
  sleep 2  # let some logs accumulate
}

teardown() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testlogs 2>/dev/null || true
}

@test "(generic:logs) shows container logs" {
  run dokku "$PLUGIN_COMMAND_PREFIX:logs" testlogs
  assert_success
  assert_contains "$output" "Ready to accept connections"
}

@test "(generic:logs -t) shows logs with timestamps" {
  run dokku "$PLUGIN_COMMAND_PREFIX:logs" testlogs -t
  assert_success
  # ISO timestamps look like 2026-...
  [[ "$output" =~ 20[0-9]{2}- ]]
}

@test "(generic:logs -n N) shows last N lines" {
  run dokku "$PLUGIN_COMMAND_PREFIX:logs" testlogs -n 1
  assert_success
  # exactly one line (or fewer)
  lines=$(echo "$output" | wc -l)
  [[ "$lines" -le 2 ]]
}
```

- [ ] **Step 2: Реализация**

```bash
#!/usr/bin/env bash
set -eo pipefail
[[ $DOKKU_TRACE ]] && set -x

PLUGIN_BASE_PATH="$(cd "$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")" && pwd)"
source "$PLUGIN_BASE_PATH/config"
source "$PLUGIN_BASE_PATH/common-functions"

shift
SERVICE=""
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--timestamps) EXTRA_ARGS+=("--timestamps"); shift ;;
    -n|--num) EXTRA_ARGS+=("--tail" "$2"); shift 2 ;;
    -f|--follow) EXTRA_ARGS+=("--follow"); shift ;;
    *)
      if [[ -z "$SERVICE" ]]; then SERVICE="$1"; else dokku_log_fail "Unexpected: $1"; fi
      shift ;;
  esac
done

[[ -z "$SERVICE" ]] && dokku_log_fail "Please specify a valid name for the service"
verify_service_name "$SERVICE" || dokku_log_fail "Invalid service name"
service_exists "$SERVICE" || dokku_log_fail "Service $SERVICE does not exist"

CONTAINER="$(service_container_name "$SERVICE")"

exec "$DOCKER_BIN" container logs "${EXTRA_ARGS[@]}" "$CONTAINER"
```

- [ ] **Step 3: commit**

```bash
chmod +x subcommands/logs
docker exec dokku-generic-test bats /var/lib/dokku/plugins/available/generic/tests/service_logs.bats
git add subcommands/logs tests/service_logs.bats commands
git commit -m "feat: subcommands/logs with -t/-n/-f"
```

---

## Self-Review

Spec coverage §3.3 + §3.4: start/stop/restart/pause/enter/exec/logs — все есть. `service_is_running` и `service_restart_internal` помогают переиспользовать логику. Status маппинг (created/running/stopped/paused/restarting) — `info` уже умеет (Plan 1).
