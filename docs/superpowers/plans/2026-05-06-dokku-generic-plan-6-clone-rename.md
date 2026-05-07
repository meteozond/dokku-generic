# dokku-generic Plan 6 — Clone / Rename

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development или superpowers:executing-plans.

**Goal:** Реализовать копирование и переименование сервисов с переносом данных volumes и (для rename) обновлением linked apps.

**Prerequisite:** Plans 1–5.

---

## Task 1: Helper `copy_volume_data` через busybox

**Files:**
- Modify: `functions`

- [ ] **Step 1: Реализация**

В `functions`:
```bash

# Copy contents of one named volume to another using a busybox helper container.
copy_volume_data() {
  local from_vol="$1" to_vol="$2"
  "$DOCKER_BIN" volume create "$to_vol" >/dev/null
  "$DOCKER_BIN" container run --rm \
    -v "$from_vol":/from:ro \
    -v "$to_vol":/to \
    "$PLUGIN_BUSYBOX_IMAGE" \
    sh -c 'cd /from && cp -a . /to/' >/dev/null
}

# Returns named volumes that belong to a service (default + per-mount sha1).
list_service_volumes() {
  local service="$1"
  "$DOCKER_BIN" volume ls --format '{{.Name}}' | grep -E "^${PLUGIN_VOLUME_PREFIX//./\\.}\.${service}(\.|$)" || true
}
```

- [ ] **Step 2: commit**

```bash
git add functions
git commit -m "feat: copy_volume_data and list_service_volumes helpers"
```

---

## Task 2: `subcommands/clone`

**Files:**
- Create: `subcommands/clone`
- Create: `tests/service_clone.bats`

- [ ] **Step 1: Tests**

```bash
#!/usr/bin/env bats

load test_helper

setup() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" src 2>/dev/null || true
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" newsvc 2>/dev/null || true
  dokku "$PLUGIN_COMMAND_PREFIX:create" src redis:7-alpine \
    --port 6379 --scheme redis \
    --env FOO=bar \
    --link-env LINKED_URL=redis://x \
    --mount /data
}

teardown() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" src 2>/dev/null || true
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" newsvc 2>/dev/null || true
}

@test "(generic:clone) copies state to new service" {
  run dokku "$PLUGIN_COMMAND_PREFIX:clone" src newsvc
  assert_success

  run cat "$PLUGIN_DATA_HOST_ROOT/newsvc/IMAGE"
  assert_output "redis:7-alpine"
  run cat "$PLUGIN_DATA_HOST_ROOT/newsvc/PORT"
  assert_output "6379"
  run cat "$PLUGIN_DATA_HOST_ROOT/newsvc/ENV"
  assert_contains "$output" "FOO=bar"
  run cat "$PLUGIN_DATA_HOST_ROOT/newsvc/LINK_ENV"
  assert_contains "$output" "LINKED_URL=redis://x"
}

@test "(generic:clone) creates separate network and starts new container" {
  dokku "$PLUGIN_COMMAND_PREFIX:clone" src newsvc

  run docker network inspect dokku.generic.newsvc
  assert_success
  run docker container inspect -f '{{.State.Status}}' dokku.generic.newsvc
  assert_output "running"
}

@test "(generic:clone) clears LINKS in new service" {
  echo "someapp" > "$PLUGIN_DATA_HOST_ROOT/src/LINKS"
  dokku "$PLUGIN_COMMAND_PREFIX:clone" src newsvc
  [[ ! -s "$PLUGIN_DATA_HOST_ROOT/newsvc/LINKS" ]]
}

@test "(generic:clone) volumes are empty by default" {
  # Write data into src's volume
  dokku "$PLUGIN_COMMAND_PREFIX:exec" src sh -c "echo 'srcdata' > /data/marker.txt"
  dokku "$PLUGIN_COMMAND_PREFIX:clone" src newsvc

  run dokku "$PLUGIN_COMMAND_PREFIX:exec" newsvc sh -c "test -f /data/marker.txt && echo found || echo missing"
  assert_output "missing"
}

@test "(generic:clone --copy-volumes) copies data" {
  dokku "$PLUGIN_COMMAND_PREFIX:exec" src sh -c "echo 'srcdata' > /data/marker.txt"
  dokku "$PLUGIN_COMMAND_PREFIX:clone" src newsvc --copy-volumes

  run dokku "$PLUGIN_COMMAND_PREFIX:exec" newsvc cat /data/marker.txt
  assert_output "srcdata"
}

@test "(generic:clone) override flags work" {
  dokku "$PLUGIN_COMMAND_PREFIX:clone" src newsvc --env FOO=newbar --port 6380
  run cat "$PLUGIN_DATA_HOST_ROOT/newsvc/ENV"
  assert_contains "$output" "FOO=newbar"
  run cat "$PLUGIN_DATA_HOST_ROOT/newsvc/PORT"
  assert_output "6380"
}

@test "(generic:clone) error when target exists" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" newsvc redis:7-alpine
  run dokku "$PLUGIN_COMMAND_PREFIX:clone" src newsvc
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
SOURCE="" TARGET=""
COPY_VOLUMES=0
declare -a OVERRIDE_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --copy-volumes) COPY_VOLUMES=1; shift ;;
    --env|--link-env|--mount|--port|--scheme|--cmd|--entrypoint|--docker-arg|--expose)
      OVERRIDE_ARGS+=("$1" "$2"); shift 2 ;;
    --env=*|--link-env=*|--mount=*|--port=*|--scheme=*|--cmd=*|--entrypoint=*|--docker-arg=*|--expose=*)
      OVERRIDE_ARGS+=("$1"); shift ;;
    -*) dokku_log_fail "Unknown flag: $1" ;;
    *)
      if   [[ -z "$SOURCE" ]]; then SOURCE="$1"
      elif [[ -z "$TARGET" ]]; then TARGET="$1"
      else dokku_log_fail "Unexpected: $1"; fi
      shift ;;
  esac
done

[[ -z "$SOURCE" ]] && dokku_log_fail "Please specify source service"
[[ -z "$TARGET" ]] && dokku_log_fail "Please specify target service name"
verify_service_name "$SOURCE" || dokku_log_fail "Invalid source name"
verify_service_name "$TARGET" || dokku_log_fail "Invalid target name"
service_exists "$SOURCE" || dokku_log_fail "Source $SOURCE does not exist"
service_exists "$TARGET" && dokku_log_fail "Target $TARGET already exists"

SOURCE_ROOT="$(service_root "$SOURCE")"
TARGET_ROOT="$(service_root "$TARGET")"

# Copy state
cp -a "$SOURCE_ROOT" "$TARGET_ROOT"

# Reset per-instance fields
rm -f "$TARGET_ROOT/LINKS" "$TARGET_ROOT/EXPOSED_PORTS" "$TARGET_ROOT/ID"
date -u +"%Y-%m-%dT%H:%M:%SZ" > "$TARGET_ROOT/CREATED_AT"

# Copy volumes if requested (must do before container start so target can mount)
if [[ $COPY_VOLUMES -eq 1 ]]; then
  while IFS= read -r vol; do
    [[ -z "$vol" ]] && continue
    new_vol="${vol/${PLUGIN_VOLUME_PREFIX}.${SOURCE}/${PLUGIN_VOLUME_PREFIX}.${TARGET}}"
    copy_volume_data "$vol" "$new_vol"
  done < <(list_service_volumes "$SOURCE")
fi

# Apply override flags via set logic — easiest: invoke `set` after start
# But we need to start first; we invoke create's restart_internal-like flow:

# Create network and run container
NETWORK="$(service_network_name "$TARGET")"
"$DOCKER_BIN" network inspect "$NETWORK" >/dev/null 2>&1 \
  || "$DOCKER_BIN" network create "$NETWORK" >/dev/null

service_restart_internal "$TARGET"

# Apply overrides
if [[ ${#OVERRIDE_ARGS[@]} -gt 0 ]]; then
  "$PLUGIN_BASE_PATH/subcommands/set" "generic:set" "$TARGET" "${OVERRIDE_ARGS[@]}"
fi

dokku_log_info2 "Cloned $SOURCE → $TARGET"
```

- [ ] **Step 3: commit**

```bash
chmod +x subcommands/clone
docker exec dokku-generic-test bats /var/lib/dokku/plugins/available/generic/tests/service_clone.bats
git add subcommands/clone tests/service_clone.bats commands
git commit -m "feat: subcommands/clone with --copy-volumes"
```

---

## Task 3: `subcommands/rename`

**Files:**
- Create: `subcommands/rename`
- Create: `tests/service_rename.bats`

- [ ] **Step 1: Tests**

```bash
#!/usr/bin/env bats

load test_helper

setup() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" oldsvc 2>/dev/null || true
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" newsvc 2>/dev/null || true
  dokku apps:destroy --force testapp 2>/dev/null || true
  dokku "$PLUGIN_COMMAND_PREFIX:create" oldsvc redis:7-alpine --port 6379 --scheme redis --mount /data
  dokku apps:create testapp
  dokku "$PLUGIN_COMMAND_PREFIX:link" oldsvc testapp
}

teardown() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" oldsvc 2>/dev/null || true
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" newsvc 2>/dev/null || true
  dokku apps:destroy --force testapp 2>/dev/null || true
}

@test "(generic:rename) moves state and keeps data" {
  dokku "$PLUGIN_COMMAND_PREFIX:exec" oldsvc sh -c "echo 'data' > /data/marker.txt"

  run dokku "$PLUGIN_COMMAND_PREFIX:rename" oldsvc newsvc
  assert_success

  [[ ! -d "$PLUGIN_DATA_HOST_ROOT/oldsvc" ]]
  [[ -d   "$PLUGIN_DATA_HOST_ROOT/newsvc" ]]

  run dokku "$PLUGIN_COMMAND_PREFIX:exec" newsvc cat /data/marker.txt
  assert_output "data"
}

@test "(generic:rename) updates docker-options of linked apps" {
  dokku "$PLUGIN_COMMAND_PREFIX:rename" oldsvc newsvc
  run dokku docker-options:report testapp
  assert_contains "$output" "--network=dokku.generic.newsvc"
  assert_not_contains "$output" "--network=dokku.generic.oldsvc"
}

@test "(generic:rename) updates link config vars" {
  dokku "$PLUGIN_COMMAND_PREFIX:rename" oldsvc newsvc
  run dokku config:get testapp NEWSVC_HOST
  assert_output "dokku.generic.newsvc"
  run dokku config:get testapp OLDSVC_HOST
  assert_output ""
}

@test "(generic:rename) error when target exists" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" newsvc redis:7-alpine
  run dokku "$PLUGIN_COMMAND_PREFIX:rename" oldsvc newsvc
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
OLD="${1:-}" NEW="${2:-}"

[[ -z "$OLD" ]] && dokku_log_fail "Please specify old service name"
[[ -z "$NEW" ]] && dokku_log_fail "Please specify new service name"
verify_service_name "$OLD" || dokku_log_fail "Invalid old name"
verify_service_name "$NEW" || dokku_log_fail "Invalid new name"
service_exists "$OLD" || dokku_log_fail "Service $OLD does not exist"
service_exists "$NEW" && dokku_log_fail "Service $NEW already exists"

OLD_ROOT="$(service_root "$OLD")"
NEW_ROOT="$(service_root "$NEW")"
OLD_CONT="$(service_container_name "$OLD")"
NEW_CONT="$(service_container_name "$NEW")"
OLD_NET="$(service_network_name "$OLD")"
NEW_NET="$(service_network_name "$NEW")"

# Read links before mutation
OLD_LINKS=()
if [[ -f "$OLD_ROOT/LINKS" ]]; then
  while IFS= read -r app; do [[ -n "$app" ]] && OLD_LINKS+=("$app"); done < "$OLD_ROOT/LINKS"
fi

# 1. Stop old container
"$DOCKER_BIN" container stop -t "$PLUGIN_STOP_TIMEOUT" "$OLD_CONT" >/dev/null 2>&1 || true

# 2. Move state
mv "$OLD_ROOT" "$NEW_ROOT"

# 3. Create new network
"$DOCKER_BIN" network create "$NEW_NET" >/dev/null 2>&1 || true

# 4. Copy volumes (named only)
while IFS= read -r vol; do
  [[ -z "$vol" ]] && continue
  new_vol="${vol/${PLUGIN_VOLUME_PREFIX}.${OLD}/${PLUGIN_VOLUME_PREFIX}.${NEW}}"
  copy_volume_data "$vol" "$new_vol"
done < <(list_service_volumes "$OLD")

# 5. Remove old container, ambassadors, network, volumes
"$DOCKER_BIN" container rm -f "$OLD_CONT" >/dev/null 2>&1 || true
for amb in $("$DOCKER_BIN" container ls -aq --filter "label=dokku.ambassador.service=$OLD"); do
  "$DOCKER_BIN" container rm -f "$amb" >/dev/null 2>&1 || true
done
"$DOCKER_BIN" network rm "$OLD_NET" >/dev/null 2>&1 || true
while IFS= read -r vol; do
  [[ -z "$vol" ]] && continue
  "$DOCKER_BIN" volume rm "$vol" >/dev/null 2>&1 || true
done < <(list_service_volumes "$OLD")

# 6. Start new container
service_restart_internal "$NEW"

# 7. Rebuild ambassadors for new
service_ambassador_rebuild "$NEW"

# 8. Update linked apps: docker-options + config
OLD_ALIAS="$(service_alias "$OLD")"
NEW_ALIAS="$(service_alias "$NEW")"

for app in "${OLD_LINKS[@]}"; do
  # docker-options
  dokku docker-options:remove "$app" build,deploy,run "--network=$OLD_NET" >/dev/null 2>&1 || true
  dokku docker-options:add    "$app" build,deploy,run "--network=$NEW_NET"

  # rewrite config keys: <OLD_ALIAS>_HOST/PORT/URL → <NEW_ALIAS>_*
  declare -a NEW_PAIRS=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    k="${line%%=*}"; v="${line#*=}"
    if [[ "$k" == "${OLD_ALIAS}_HOST" || "$k" == "${OLD_ALIAS}_PORT" || "$k" == "${OLD_ALIAS}_URL" ]]; then
      suffix="${k##${OLD_ALIAS}_}"
      # update value: replace OLD_CONT with NEW_CONT
      v="${v//$OLD_CONT/$NEW_CONT}"
      NEW_PAIRS+=("${NEW_ALIAS}_${suffix}=$v")
      dokku config:unset --no-restart "$app" "$k" >/dev/null 2>&1 || true
    fi
  done < <(dokku config:export --format=envfile "$app")
  if [[ ${#NEW_PAIRS[@]} -gt 0 ]]; then
    dokku config:set --no-restart "$app" "${NEW_PAIRS[@]}"
  fi

  # rewrite link-env values that contain OLD_CONT
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    k="${line%%=*}"; v="${line#*=}"
    if [[ "$v" == *"$OLD_CONT"* ]]; then
      new_v="${v//$OLD_CONT/$NEW_CONT}"
      dokku config:set --no-restart "$app" "$k=$new_v"
    fi
  done < <(dokku config:export --format=envfile "$app")

  dokku ps:restart "$app" >/dev/null 2>&1 || true
done

dokku_log_info2 "Renamed $OLD → $NEW"
```

- [ ] **Step 3: commit**

```bash
chmod +x subcommands/rename
docker exec dokku-generic-test bats /var/lib/dokku/plugins/available/generic/tests/service_rename.bats
git add subcommands/rename tests/service_rename.bats commands
git commit -m "feat: subcommands/rename with volumes and link rewiring"
```

---

## Self-Review

Coverage §3.1 clone/rename: оба покрыты. Limitation: rollback при ошибке rename — не делается, ошибка → state в промежуточном виде. В Spec §3 это явно допускается: "Не делаем автоматический rollback — он сложнее самой операции". Smoke-тестирование это покажет.
