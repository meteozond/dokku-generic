# dokku-generic Plan 5 — Expose / Unexpose (Ambassador)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development или superpowers:executing-plans.

**Goal:** Реализовать публикацию портов сервиса наружу хоста через ambassador-контейнер. Сам сервисный контейнер не трогается.

**Prerequisite:** Plans 1–4.

---

## Task 1: Helper `service_ambassador_*`

**Files:**
- Modify: `functions`

- [ ] **Step 1: Failing tests** (unit-level, проверяют формирование команд)

В `tests/unit_helpers.bats`:
```bash

@test "service_ambassador_name returns <container>.ambassador" {
  run service_ambassador_name "myservice"
  assert_output "dokku-generic-myservice.ambassador"
}
```

- [ ] **Step 2: Реализация**

В `functions`:
```bash

service_ambassador_name() {
  printf '%s.ambassador' "$(service_container_name "$1")"
}

# Rebuild ambassador with current EXPOSED_PORTS. Stops old, starts new.
service_ambassador_rebuild() {
  local service="$1"
  local amb network root
  amb="$(service_ambassador_name "$service")"
  network="$(service_network_name "$service")"
  root="$(service_root "$service")"

  # Tear down existing
  "$DOCKER_BIN" container rm -f "$amb" >/dev/null 2>&1 || true

  # If no EXPOSED_PORTS, we're done
  [[ ! -s "$root/EXPOSED_PORTS" ]] && return 0

  # Build -p flags
  local -a port_flags=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    port_flags+=("-p" "$line")
  done < "$root/EXPOSED_PORTS"

  local container_dns container_port
  container_dns="$(service_container_name "$service")"
  # Use first exposed pair's container port as default ambassador target;
  # ambassador supports multiple via positional args (we re-target each)
  # The dokku/ambassador image accepts: <target_host> <target_port>
  # For multi-port, we run one ambassador per port → simpler.

  # Tear down per-port ambassadors first
  for amb_port_container in $("$DOCKER_BIN" container ls -aq --filter "label=dokku.ambassador.service=$service"); do
    "$DOCKER_BIN" container rm -f "$amb_port_container" >/dev/null 2>&1 || true
  done

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local host_port="${line%%:*}" cont_port="${line#*:}"
    "$DOCKER_BIN" container run -d \
      --name "${amb}.${host_port}" \
      --network "$network" \
      --restart always \
      --label dokku=ambassador \
      --label "dokku.ambassador=$PLUGIN_SERVICE" \
      --label "dokku.ambassador.service=$service" \
      -p "$line" \
      "$PLUGIN_AMBASSADOR_IMAGE" \
      "$container_dns" "$cont_port" >/dev/null
  done < "$root/EXPOSED_PORTS"
}
```

- [ ] **Step 3: commit**

```bash
git add functions tests/unit_helpers.bats
git commit -m "feat: service_ambassador_name and rebuild helpers"
```

---

## Task 2: `subcommands/expose`

**Files:**
- Create: `subcommands/expose`
- Create: `tests/service_expose.bats`

- [ ] **Step 1: Tests**

```bash
#!/usr/bin/env bats

load test_helper

setup() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testexp 2>/dev/null || true
  dokku "$PLUGIN_COMMAND_PREFIX:create" testexp redis:7-alpine --port 6379
}

teardown() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testexp 2>/dev/null || true
}

@test "(generic:expose) starts ambassador with port mapping" {
  run dokku "$PLUGIN_COMMAND_PREFIX:expose" testexp 16379:6379
  assert_success

  run cat "$PLUGIN_DATA_HOST_ROOT/testexp/EXPOSED_PORTS"
  assert_contains "$output" "16379:6379"

  run docker container inspect dokku-generic-testexp.ambassador.16379
  assert_success
}

@test "(generic:expose) does NOT restart service container" {
  initial_id=$(docker container inspect -f '{{.Id}}' dokku-generic-testexp)
  dokku "$PLUGIN_COMMAND_PREFIX:expose" testexp 16379:6379
  new_id=$(docker container inspect -f '{{.Id}}' dokku-generic-testexp)
  [[ "$initial_id" == "$new_id" ]]
}

@test "(generic:expose) error on bad spec" {
  run dokku "$PLUGIN_COMMAND_PREFIX:expose" testexp 16379
  assert_failure
}

@test "(generic:expose) supports multi-port (calls multiple times)" {
  dokku "$PLUGIN_COMMAND_PREFIX:expose" testexp 16379:6379
  dokku "$PLUGIN_COMMAND_PREFIX:expose" testexp 26379:6379
  run cat "$PLUGIN_DATA_HOST_ROOT/testexp/EXPOSED_PORTS"
  assert_contains "$output" "16379:6379"
  assert_contains "$output" "26379:6379"
}

@test "(generic:expose) is idempotent for same spec" {
  dokku "$PLUGIN_COMMAND_PREFIX:expose" testexp 16379:6379
  run dokku "$PLUGIN_COMMAND_PREFIX:expose" testexp 16379:6379
  assert_success
  count=$(grep -c "^16379:6379$" "$PLUGIN_DATA_HOST_ROOT/testexp/EXPOSED_PORTS")
  [[ "$count" -eq 1 ]]
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
SPEC="${2:-}"

[[ -z "$SERVICE" ]] && dokku_log_fail "Please specify a service"
[[ -z "$SPEC"    ]] && dokku_log_fail "Please specify HOST_PORT:CONTAINER_PORT"
verify_service_name "$SERVICE" || dokku_log_fail "Invalid service name"
service_exists "$SERVICE" || dokku_log_fail "Service $SERVICE does not exist"

if [[ ! "$SPEC" =~ ^[0-9]+:[0-9]+$ ]]; then
  dokku_log_fail "Invalid port spec: $SPEC (expected HOST:CONTAINER)"
fi

ROOT="$(service_root "$SERVICE")"

# Idempotent: skip if already in EXPOSED_PORTS
if [[ -f "$ROOT/EXPOSED_PORTS" ]] && grep -qxF "$SPEC" "$ROOT/EXPOSED_PORTS"; then
  dokku_log_info1 "Port $SPEC already exposed for $SERVICE"
  exit 0
fi

echo "$SPEC" >> "$ROOT/EXPOSED_PORTS"

service_ambassador_rebuild "$SERVICE"

dokku_log_info2 "Exposed $SPEC for $SERVICE"
```

- [ ] **Step 3: commit**

```bash
chmod +x subcommands/expose
# add generic:expose to commands
docker exec dokku-generic-test bats /var/lib/dokku/plugins/available/generic/tests/service_expose.bats
git add subcommands/expose tests/service_expose.bats commands
git commit -m "feat: subcommands/expose with ambassador per-port"
```

---

## Task 3: `subcommands/unexpose`

**Files:**
- Create: `subcommands/unexpose`
- Create: `tests/service_unexpose.bats`

- [ ] **Step 1: Tests**

```bash
#!/usr/bin/env bats

load test_helper

setup() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testexp 2>/dev/null || true
  dokku "$PLUGIN_COMMAND_PREFIX:create" testexp redis:7-alpine --port 6379
  dokku "$PLUGIN_COMMAND_PREFIX:expose" testexp 16379:6379
  dokku "$PLUGIN_COMMAND_PREFIX:expose" testexp 26379:6379
}

teardown() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testexp 2>/dev/null || true
}

@test "(generic:unexpose) removes specific port" {
  run dokku "$PLUGIN_COMMAND_PREFIX:unexpose" testexp 16379:6379
  assert_success
  run cat "$PLUGIN_DATA_HOST_ROOT/testexp/EXPOSED_PORTS"
  assert_not_contains "$output" "16379:6379"
  assert_contains "$output" "26379:6379"

  run docker container inspect dokku-generic-testexp.ambassador.16379
  assert_failure
  run docker container inspect dokku-generic-testexp.ambassador.26379
  assert_success
}

@test "(generic:unexpose) removes ambassador entirely after last port" {
  dokku "$PLUGIN_COMMAND_PREFIX:unexpose" testexp 16379:6379
  dokku "$PLUGIN_COMMAND_PREFIX:unexpose" testexp 26379:6379

  for amb in $(docker container ls --filter "label=dokku.ambassador.service=testexp" --format "{{.Names}}"); do
    flunk "ambassador $amb still exists"
  done
}

@test "(generic:unexpose) error when port not exposed" {
  run dokku "$PLUGIN_COMMAND_PREFIX:unexpose" testexp 99999:9999
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
SPEC="${2:-}"

[[ -z "$SERVICE" ]] && dokku_log_fail "Please specify a service"
[[ -z "$SPEC"    ]] && dokku_log_fail "Please specify HOST_PORT:CONTAINER_PORT"
verify_service_name "$SERVICE" || dokku_log_fail "Invalid service name"
service_exists "$SERVICE" || dokku_log_fail "Service $SERVICE does not exist"

ROOT="$(service_root "$SERVICE")"

if [[ ! -f "$ROOT/EXPOSED_PORTS" ]] || ! grep -qxF "$SPEC" "$ROOT/EXPOSED_PORTS"; then
  dokku_log_fail "Port $SPEC is not exposed for $SERVICE"
fi

# Remove from EXPOSED_PORTS
tmp="$(mktemp "$ROOT/.expose.XXXXXX")"
grep -vxF "$SPEC" "$ROOT/EXPOSED_PORTS" > "$tmp" || true
mv "$tmp" "$ROOT/EXPOSED_PORTS"

service_ambassador_rebuild "$SERVICE"

dokku_log_info2 "Unexposed $SPEC for $SERVICE"
```

- [ ] **Step 3: commit**

```bash
chmod +x subcommands/unexpose
docker exec dokku-generic-test bats /var/lib/dokku/plugins/available/generic/tests/service_unexpose.bats
git add subcommands/unexpose tests/service_unexpose.bats commands
git commit -m "feat: subcommands/unexpose"
```

---

## Self-Review

Coverage §3.6 expose/unexpose: одна ambassador-инстанция на каждый порт (упрощает rebuild и не требует reload-логики), помечается label'ом для последующего сбора. Ambassador использует наш `PLUGIN_AMBASSADOR_IMAGE` через 2-х аргумент target_host target_port. Сервис не рестартует при expose/unexpose. `destroy` (Plan 1) сам удаляет ambassador-ы по lable filter — проверить в smoke.
