# dokku-generic Plan 7 — Lifecycle Hooks

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development или superpowers:executing-plans.

**Goal:** Реализовать lifecycle-хуки, которые Dokku вызывает при операциях с приложениями.

**Prerequisite:** Plans 1–6.

**Hooks:**
- `pre-start <app>` — перед стартом app поднимает остановленные linked сервисы.
- `pre-delete <app>` — перед удалением app убирает его из `LINKS` всех сервисов.
- `post-app-clone-setup <old> <new>` — клонирование app переносит линки.
- `post-app-rename-setup <old> <new>` — rename app обновляет LINKS.

---

## Task 1: `pre-start`

**Files:**
- Create: `pre-start`
- Create: `tests/hook_pre_start.bats`

- [ ] **Step 1: Tests**

```bash
#!/usr/bin/env bats

load test_helper

setup() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testpg 2>/dev/null || true
  dokku apps:destroy --force testapp 2>/dev/null || true
  dokku "$PLUGIN_COMMAND_PREFIX:create" testpg redis:7-alpine --port 6379
  dokku apps:create testapp
  dokku "$PLUGIN_COMMAND_PREFIX:link" testpg testapp
}

teardown() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testpg 2>/dev/null || true
  dokku apps:destroy --force testapp 2>/dev/null || true
}

@test "(hook pre-start) starts stopped linked services" {
  dokku "$PLUGIN_COMMAND_PREFIX:stop" testpg
  run dokku ps:start testapp 2>&1 || true
  run docker container inspect -f '{{.State.Status}}' dokku.generic.testpg
  assert_output "running"
}

@test "(hook pre-start) is no-op when service running" {
  run /var/lib/dokku/plugins/available/generic/pre-start testapp
  assert_success
}
```

- [ ] **Step 2: Реализация**

```bash
#!/usr/bin/env bash
set -eo pipefail
[[ $DOKKU_TRACE ]] && set -x

PLUGIN_BASE_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$PLUGIN_BASE_PATH/config"
source "$PLUGIN_BASE_PATH/common-functions"
source "$PLUGIN_BASE_PATH/functions"

APP="$1"
[[ -z "$APP" ]] && exit 0

while IFS= read -r service; do
  [[ -z "$service" ]] && continue
  links_file="$(service_root "$service")/LINKS"
  [[ -s "$links_file" ]] || continue
  if ! grep -qxF "$APP" "$links_file"; then continue; fi

  if service_is_running "$service"; then continue; fi

  status=$("$DOCKER_BIN" container inspect -f '{{.State.Status}}' "$(service_container_name "$service")" 2>/dev/null || echo "")
  if [[ "$status" == "restarting" ]]; then
    dokku_log_warn "$PLUGIN_SERVICE service $service is restarting"
    continue
  fi
  dokku_log_warn "$PLUGIN_SERVICE service $service is not running, starting"
  "$PLUGIN_BASE_PATH/subcommands/start" "generic:start" "$service"
done < <(fn-services-list)
```

- [ ] **Step 3: commit**

```bash
chmod +x pre-start
docker exec dokku-generic-test bats /var/lib/dokku/plugins/available/generic/tests/hook_pre_start.bats
git add pre-start tests/hook_pre_start.bats
git commit -m "feat: pre-start hook auto-starts linked services"
```

---

## Task 2: `pre-delete`

**Files:**
- Create: `pre-delete`
- Create: `tests/hook_pre_delete.bats`

- [ ] **Step 1: Tests**

```bash
#!/usr/bin/env bats

load test_helper

setup() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testpg 2>/dev/null || true
  dokku apps:destroy --force testapp 2>/dev/null || true
  dokku "$PLUGIN_COMMAND_PREFIX:create" testpg redis:7-alpine --port 6379
  dokku apps:create testapp
  dokku "$PLUGIN_COMMAND_PREFIX:link" testpg testapp
}

teardown() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testpg 2>/dev/null || true
  dokku apps:destroy --force testapp 2>/dev/null || true
}

@test "(hook pre-delete) removes app from LINKS when app destroyed" {
  dokku apps:destroy --force testapp
  run cat "$PLUGIN_DATA_HOST_ROOT/testpg/LINKS"
  assert_not_contains "$output" "testapp"
}
```

- [ ] **Step 2: Реализация**

```bash
#!/usr/bin/env bash
set -eo pipefail
[[ $DOKKU_TRACE ]] && set -x

PLUGIN_BASE_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$PLUGIN_BASE_PATH/config"
source "$PLUGIN_BASE_PATH/common-functions"

APP="$1"
[[ -z "$APP" ]] && exit 0

while IFS= read -r service; do
  [[ -z "$service" ]] && continue
  links_file="$(service_root "$service")/LINKS"
  [[ -f "$links_file" ]] || continue
  if grep -qxF "$APP" "$links_file"; then
    tmp="$(mktemp "$(dirname "$links_file")/.links.XXXXXX")"
    grep -vxF "$APP" "$links_file" > "$tmp" || true
    mv "$tmp" "$links_file"
    dokku_log_verbose "Removed $APP from $service LINKS"
  fi
done < <(fn-services-list)
```

- [ ] **Step 3: commit**

```bash
chmod +x pre-delete
docker exec dokku-generic-test bats /var/lib/dokku/plugins/available/generic/tests/hook_pre_delete.bats
git add pre-delete tests/hook_pre_delete.bats
git commit -m "feat: pre-delete hook cleans up LINKS"
```

---

## Task 3: `post-app-clone-setup`

**Files:**
- Create: `post-app-clone-setup`
- Create: `tests/hook_post_app_clone_setup.bats`

- [ ] **Step 1: Tests**

```bash
#!/usr/bin/env bats

load test_helper

setup() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testpg 2>/dev/null || true
  dokku apps:destroy --force srcapp 2>/dev/null || true
  dokku apps:destroy --force dstapp 2>/dev/null || true
  dokku "$PLUGIN_COMMAND_PREFIX:create" testpg redis:7-alpine --port 6379
  dokku apps:create srcapp
  dokku "$PLUGIN_COMMAND_PREFIX:link" testpg srcapp
}

teardown() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testpg 2>/dev/null || true
  dokku apps:destroy --force srcapp 2>/dev/null || true
  dokku apps:destroy --force dstapp 2>/dev/null || true
}

@test "(hook post-app-clone-setup) propagates link to clone" {
  dokku apps:clone srcapp dstapp
  run cat "$PLUGIN_DATA_HOST_ROOT/testpg/LINKS"
  assert_contains "$output" "dstapp"
  run dokku config:get dstapp TESTPG_HOST
  assert_output "dokku.generic.testpg"
}
```

- [ ] **Step 2: Реализация**

```bash
#!/usr/bin/env bash
set -eo pipefail
[[ $DOKKU_TRACE ]] && set -x

PLUGIN_BASE_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$PLUGIN_BASE_PATH/config"
source "$PLUGIN_BASE_PATH/common-functions"
source "$PLUGIN_BASE_PATH/functions"

OLD_APP="$1"
NEW_APP="$2"
[[ -z "$OLD_APP" || -z "$NEW_APP" ]] && exit 0

while IFS= read -r service; do
  [[ -z "$service" ]] && continue
  links_file="$(service_root "$service")/LINKS"
  [[ -f "$links_file" ]] || continue
  if grep -qxF "$OLD_APP" "$links_file"; then
    "$PLUGIN_BASE_PATH/subcommands/link" "generic:link" "$service" "$NEW_APP" || true
  fi
done < <(fn-services-list)
```

- [ ] **Step 3: commit**

```bash
chmod +x post-app-clone-setup
docker exec dokku-generic-test bats /var/lib/dokku/plugins/available/generic/tests/hook_post_app_clone_setup.bats
git add post-app-clone-setup tests/hook_post_app_clone_setup.bats
git commit -m "feat: post-app-clone-setup hook"
```

---

## Task 4: `post-app-rename-setup`

**Files:**
- Create: `post-app-rename-setup`
- Create: `tests/hook_post_app_rename_setup.bats`

- [ ] **Step 1: Tests**

```bash
#!/usr/bin/env bats

load test_helper

setup() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testpg 2>/dev/null || true
  dokku apps:destroy --force srcapp 2>/dev/null || true
  dokku apps:destroy --force dstapp 2>/dev/null || true
  dokku "$PLUGIN_COMMAND_PREFIX:create" testpg redis:7-alpine --port 6379
  dokku apps:create srcapp
  dokku "$PLUGIN_COMMAND_PREFIX:link" testpg srcapp
}

teardown() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testpg 2>/dev/null || true
  dokku apps:destroy --force dstapp 2>/dev/null || true
}

@test "(hook post-app-rename-setup) updates LINKS file on rename" {
  dokku apps:rename srcapp dstapp
  run cat "$PLUGIN_DATA_HOST_ROOT/testpg/LINKS"
  assert_contains "$output" "dstapp"
  assert_not_contains "$output" "srcapp"
}
```

- [ ] **Step 2: Реализация**

```bash
#!/usr/bin/env bash
set -eo pipefail
[[ $DOKKU_TRACE ]] && set -x

PLUGIN_BASE_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$PLUGIN_BASE_PATH/config"
source "$PLUGIN_BASE_PATH/common-functions"

OLD_APP="$1"
NEW_APP="$2"
[[ -z "$OLD_APP" || -z "$NEW_APP" ]] && exit 0

while IFS= read -r service; do
  [[ -z "$service" ]] && continue
  links_file="$(service_root "$service")/LINKS"
  [[ -f "$links_file" ]] || continue
  if grep -qxF "$OLD_APP" "$links_file"; then
    sed -i "s/^${OLD_APP}\$/${NEW_APP}/" "$links_file"
  fi
done < <(fn-services-list)
```

- [ ] **Step 3: commit**

```bash
chmod +x post-app-rename-setup
docker exec dokku-generic-test bats /var/lib/dokku/plugins/available/generic/tests/hook_post_app_rename_setup.bats
git add post-app-rename-setup tests/hook_post_app_rename_setup.bats
git commit -m "feat: post-app-rename-setup hook"
```

---

## Task 5: `service-list` (для интеграции с `dokku ls`)

**Files:**
- Create: `service-list`

- [ ] **Step 1: Реализация**

```bash
#!/usr/bin/env bash
set -eo pipefail
PLUGIN_BASE_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$PLUGIN_BASE_PATH/config"
source "$PLUGIN_BASE_PATH/common-functions"

while IFS= read -r service; do
  [[ -z "$service" ]] && continue
  echo "$service"
done < <(fn-services-list)
```

- [ ] **Step 2: commit**

```bash
chmod +x service-list
git add service-list
git commit -m "feat: service-list for dokku ls integration"
```

---

## Self-Review

Coverage §5.3 lifecycle hooks: pre-start/pre-delete/post-app-clone-setup/post-app-rename-setup — все есть. service-list для `dokku ls` — добавлен. Все хуки идемпотентны и no-op при отсутствии связей.
