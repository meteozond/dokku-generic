# dokku-generic Plan 4 — Linking (link / unlink / linked / links / app-links / promote)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development или superpowers:executing-plans.

**Goal:** Реализовать привязку сервисов к приложениям Dokku: автогенерация `<PREFIX>_HOST/PORT/URL`, проброс `--link-env`, добавление сети сервиса в `docker-options` приложения, обработка alias-конфликтов.

**Prerequisite:** Plans 1–3.

---

## Task 1: Helper `service_alias` и `service_url`

**Files:**
- Modify: `functions`
- Modify: `tests/unit_helpers.bats`

- [ ] **Step 1: Failing tests**

```bash

@test "service_alias returns uppercase service name with - and . to _" {
  run service_alias "my-svc"
  assert_output "MY_SVC"
}

@test "service_alias handles dots" {
  run service_alias "my.svc"
  assert_output "MY_SVC"
}

@test "service_alias plain name uppercased" {
  run service_alias "pg"
  assert_output "PG"
}

@test "service_url returns scheme://container:port" {
  local tmp
  tmp=$(mktemp -d)
  PLUGIN_DATA_ROOT="$tmp"
  mkdir -p "$tmp/pg"
  echo "5432" > "$tmp/pg/PORT"
  echo "postgres" > "$tmp/pg/SCHEME"
  run service_url "pg"
  assert_output "postgres://dokku.generic.pg:5432"
  rm -rf "$tmp"
}

@test "service_url returns empty when no port" {
  local tmp
  tmp=$(mktemp -d)
  PLUGIN_DATA_ROOT="$tmp"
  mkdir -p "$tmp/pg"
  echo "tcp" > "$tmp/pg/SCHEME"
  run service_url "pg"
  assert_output ""
  rm -rf "$tmp"
}
```

- [ ] **Step 2: Реализация в `functions`**

```bash

service_alias() {
  local s="$1"
  s="${s//-/_}"
  s="${s//./_}"
  printf '%s' "$s" | tr '[:lower:]' '[:upper:]'
}

service_url() {
  local service="$1"
  local root port scheme
  root="$(service_root "$service")"
  port=$(<"$root/PORT" 2>/dev/null || echo "")
  scheme=$(<"$root/SCHEME" 2>/dev/null || echo "tcp")
  [[ -z "$port" ]] && return 0
  printf '%s://%s:%s' "$scheme" "$(service_container_name "$service")" "$port"
}

# Returns the next available alias suffix for app config (e.g. PG, PG2, PG3).
service_alternative_alias() {
  local app="$1" base_alias="$2"
  local existing
  existing=$(dokku config:get --no-restart "$app" "${base_alias}_URL" 2>/dev/null || true)
  if [[ -z "$existing" ]]; then
    printf '%s' "$base_alias"
    return 0
  fi
  local i=2
  while :; do
    existing=$(dokku config:get --no-restart "$app" "${base_alias}${i}_URL" 2>/dev/null || true)
    if [[ -z "$existing" ]]; then
      printf '%s%d' "$base_alias" "$i"
      return 0
    fi
    ((i++))
    [[ $i -gt 99 ]] && return 1
  done
}
```

- [ ] **Step 3: commit**

```bash
git add functions tests/unit_helpers.bats
git commit -m "feat: service_alias, service_url, service_alternative_alias"
```

---

## Task 2: `subcommands/link`

**Files:**
- Create: `subcommands/link`
- Create: `tests/service_link.bats`

- [ ] **Step 1: Failing tests**

```bash
#!/usr/bin/env bats

load test_helper

setup() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testpg 2>/dev/null || true
  dokku apps:destroy --force testapp 2>/dev/null || true
  dokku "$PLUGIN_COMMAND_PREFIX:create" testpg redis:7-alpine --port 6379 --scheme redis --link-env LINKED=yes
  dokku apps:create testapp
}

teardown() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testpg 2>/dev/null || true
  dokku apps:destroy --force testapp 2>/dev/null || true
}

@test "(generic:link) creates network connection and config" {
  run dokku "$PLUGIN_COMMAND_PREFIX:link" testpg testapp
  assert_success

  # LINKS file updated
  run cat "$PLUGIN_DATA_HOST_ROOT/testpg/LINKS"
  assert_contains "$output" "testapp"

  # docker-options has --network
  run dokku docker-options:report testapp
  assert_contains "$output" "--network=dokku.generic.testpg"

  # config has TESTPG_URL/HOST/PORT
  run dokku config:get testapp TESTPG_URL
  assert_output "redis://dokku.generic.testpg:6379"
  run dokku config:get testapp TESTPG_HOST
  assert_output "dokku.generic.testpg"
  run dokku config:get testapp TESTPG_PORT
  assert_output "6379"

  # custom link-env propagated
  run dokku config:get testapp LINKED
  assert_output "yes"
}

@test "(generic:link --alias) uses custom prefix" {
  dokku "$PLUGIN_COMMAND_PREFIX:link" testpg testapp --alias DATABASE
  run dokku config:get testapp DATABASE_URL
  assert_output "redis://dokku.generic.testpg:6379"
  run dokku config:get testapp TESTPG_URL
  assert_output ""
}

@test "(generic:link) error when already linked" {
  dokku "$PLUGIN_COMMAND_PREFIX:link" testpg testapp
  run dokku "$PLUGIN_COMMAND_PREFIX:link" testpg testapp
  assert_failure
  assert_contains "$output" "Already linked"
}

@test "(generic:link) generates alternative prefix when default occupied" {
  # First link uses TESTPG; second link of another svc with same auto-prefix should bump
  dokku "$PLUGIN_COMMAND_PREFIX:create" testpg2 redis:7-alpine --port 6379 --scheme redis
  dokku "$PLUGIN_COMMAND_PREFIX:link" testpg testapp
  dokku "$PLUGIN_COMMAND_PREFIX:link" testpg2 testapp --alias TESTPG
  run dokku config:get testapp TESTPG2_URL
  assert_contains "$output" "dokku.generic.testpg2"
  dokku "$PLUGIN_COMMAND_PREFIX:unlink" testpg2 testapp
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testpg2
}

@test "(generic:link) error when app missing" {
  run dokku "$PLUGIN_COMMAND_PREFIX:link" testpg nonexistent
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
APP=""
ALIAS_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --alias) ALIAS_OVERRIDE="$2"; shift 2 ;;
    --alias=*) ALIAS_OVERRIDE="${1#--alias=}"; shift ;;
    -*) dokku_log_fail "Unknown flag: $1" ;;
    *)
      if   [[ -z "$SERVICE" ]]; then SERVICE="$1"
      elif [[ -z "$APP"     ]]; then APP="$1"
      else dokku_log_fail "Unexpected: $1"; fi
      shift ;;
  esac
done

[[ -z "$SERVICE" ]] && dokku_log_fail "Please specify a valid service name"
[[ -z "$APP"     ]] && dokku_log_fail "Please specify a valid app name"
verify_service_name "$SERVICE" || dokku_log_fail "Invalid service name"
service_exists "$SERVICE" || dokku_log_fail "Service $SERVICE does not exist"

if ! dokku apps:exists "$APP" >/dev/null 2>&1; then
  dokku_log_fail "App $APP does not exist (try: dokku apps:create $APP)"
fi

ROOT="$(service_root "$SERVICE")"
NETWORK="$(service_network_name "$SERVICE")"
LINKS_FILE="$ROOT/LINKS"

# Already linked?
if grep -qxF "$APP" "$LINKS_FILE" 2>/dev/null; then
  dokku_log_fail "Already linked: $APP"
fi

# Determine alias
if [[ -n "$ALIAS_OVERRIDE" ]]; then
  ALIAS="$ALIAS_OVERRIDE"
else
  ALIAS="$(service_alternative_alias "$APP" "$(service_alias "$SERVICE")")"
fi

# Add app to LINKS file
echo "$APP" >> "$LINKS_FILE"

# Add network to docker-options
dokku docker-options:add "$APP" build,deploy,run "--network=$NETWORK"

# Build and apply env
declare -a CONFIG_ARGS=()
CONFIG_ARGS+=("${ALIAS}_HOST=$(service_container_name "$SERVICE")")

if [[ -s "$ROOT/PORT" ]]; then
  PORT=$(<"$ROOT/PORT")
  CONFIG_ARGS+=("${ALIAS}_PORT=$PORT")
  URL=$(service_url "$SERVICE")
  CONFIG_ARGS+=("${ALIAS}_URL=$URL")
fi

# Append link-env vars
if [[ -f "$ROOT/LINK_ENV" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    key="${line%%=*}"; val="${line#*=}"
    CONFIG_ARGS+=("$key=$(env_unescape "$val")")
  done < "$ROOT/LINK_ENV"
fi

dokku config:set "$APP" "${CONFIG_ARGS[@]}"

dokku_log_info2 "$PLUGIN_SERVICE service $SERVICE linked to $APP"
```

- [ ] **Step 3: Update `commands` and commit**

```bash
chmod +x subcommands/link
# add generic:link to commands case
docker exec dokku-generic-test bats /var/lib/dokku/plugins/available/generic/tests/service_link.bats
git add subcommands/link tests/service_link.bats commands
git commit -m "feat: subcommands/link with auto-prefix and alias resolution"
```

---

## Task 3: `subcommands/unlink`

**Files:**
- Create: `subcommands/unlink`
- Create: `tests/service_unlink.bats`

- [ ] **Step 1: Tests**

```bash
#!/usr/bin/env bats

load test_helper

setup() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testpg 2>/dev/null || true
  dokku apps:destroy --force testapp 2>/dev/null || true
  dokku "$PLUGIN_COMMAND_PREFIX:create" testpg redis:7-alpine --port 6379 --scheme redis
  dokku apps:create testapp
  dokku "$PLUGIN_COMMAND_PREFIX:link" testpg testapp
}

teardown() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testpg 2>/dev/null || true
  dokku apps:destroy --force testapp 2>/dev/null || true
}

@test "(generic:unlink) removes config and docker-options" {
  run dokku "$PLUGIN_COMMAND_PREFIX:unlink" testpg testapp
  assert_success

  run cat "$PLUGIN_DATA_HOST_ROOT/testpg/LINKS"
  assert_not_contains "$output" "testapp"

  run dokku docker-options:report testapp
  assert_not_contains "$output" "--network=dokku.generic.testpg"

  run dokku config:get testapp TESTPG_URL
  assert_output ""
}

@test "(generic:unlink) error when not linked" {
  dokku "$PLUGIN_COMMAND_PREFIX:unlink" testpg testapp
  run dokku "$PLUGIN_COMMAND_PREFIX:unlink" testpg testapp
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
APP="${2:-}"

[[ -z "$SERVICE" ]] && dokku_log_fail "Please specify a valid service name"
[[ -z "$APP"     ]] && dokku_log_fail "Please specify a valid app name"
verify_service_name "$SERVICE" || dokku_log_fail "Invalid service name"
service_exists "$SERVICE" || dokku_log_fail "Service $SERVICE does not exist"

ROOT="$(service_root "$SERVICE")"
NETWORK="$(service_network_name "$SERVICE")"
LINKS_FILE="$ROOT/LINKS"

if ! grep -qxF "$APP" "$LINKS_FILE" 2>/dev/null; then
  dokku_log_fail "Service $SERVICE is not linked to $APP"
fi

# Remove --network option
dokku docker-options:remove "$APP" build,deploy,run "--network=$NETWORK" 2>/dev/null || true

# Remove config keys: <PREFIX>_HOST/PORT/URL where prefix matches.
# We rely on stored alias — for simplicity, rebuild what we set originally:
#   default alias = service_alias(SERVICE); if --alias was used we don't track it (limitation).
# Mitigation: try both default and any *_URL pointing to our network DNS name.
DNS="$(service_container_name "$SERVICE")"
ALL_KEYS=$(dokku config:export --format=docker-args "$APP" 2>/dev/null | tr ' ' '\n' | grep '^-e' | sed 's/^-e //; s/=.*//' | sort -u)

while IFS= read -r key; do
  [[ -z "$key" ]] && continue
  val=$(dokku config:get --no-restart "$APP" "$key" 2>/dev/null || true)
  if [[ "$val" == *"$DNS"* ]]; then
    dokku config:unset --no-restart "$APP" "$key" >/dev/null 2>&1 || true
  fi
done <<< "$ALL_KEYS"

# Also unset any keys matching link-env names declared on service
if [[ -f "$ROOT/LINK_ENV" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    key="${line%%=*}"
    dokku config:unset --no-restart "$APP" "$key" >/dev/null 2>&1 || true
  done < "$ROOT/LINK_ENV"
fi

# Remove app from LINKS file
tmp="$(mktemp "$ROOT/.links.XXXXXX")"
grep -vxF "$APP" "$LINKS_FILE" > "$tmp" || true
mv "$tmp" "$LINKS_FILE"

# Trigger app restart (no-restart wasn't set on docker-options:remove, so already restarting)
dokku ps:restart "$APP" >/dev/null 2>&1 || true

dokku_log_info2 "$PLUGIN_SERVICE service $SERVICE unlinked from $APP"
```

- [ ] **Step 3: commit**

```bash
chmod +x subcommands/unlink
docker exec dokku-generic-test bats /var/lib/dokku/plugins/available/generic/tests/service_unlink.bats
git add subcommands/unlink tests/service_unlink.bats commands
git commit -m "feat: subcommands/unlink with config and network cleanup"
```

---

## Task 4: `subcommands/linked` / `links` / `app-links`

**Files:**
- Create: `subcommands/linked`
- Create: `subcommands/links`
- Create: `subcommands/app-links`
- Create: `tests/service_linked.bats`
- Create: `tests/service_links.bats`
- Create: `tests/service_app-links.bats`

- [ ] **Step 1: `subcommands/linked` (apps linked to a service)**

```bash
#!/usr/bin/env bash
set -eo pipefail
PLUGIN_BASE_PATH="$(cd "$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")" && pwd)"
source "$PLUGIN_BASE_PATH/config"
source "$PLUGIN_BASE_PATH/common-functions"

shift
SERVICE="${1:-}"
[[ -z "$SERVICE" ]] && dokku_log_fail "Please specify a service"
service_exists "$SERVICE" || dokku_log_fail "Service $SERVICE does not exist"
LINKS_FILE="$(service_root "$SERVICE")/LINKS"
[[ -s "$LINKS_FILE" ]] && cat "$LINKS_FILE" || echo "(no apps linked)"
```

- [ ] **Step 2: `subcommands/links` (services linked to an app)**

```bash
#!/usr/bin/env bash
set -eo pipefail
PLUGIN_BASE_PATH="$(cd "$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")" && pwd)"
source "$PLUGIN_BASE_PATH/config"
source "$PLUGIN_BASE_PATH/common-functions"

shift
APP="${1:-}"
[[ -z "$APP" ]] && dokku_log_fail "Please specify an app"

found=0
while IFS= read -r service; do
  [[ -z "$service" ]] && continue
  if grep -qxF "$APP" "$(service_root "$service")/LINKS" 2>/dev/null; then
    echo "$service"
    found=1
  fi
done < <(fn-services-list)
[[ $found -eq 0 ]] && echo "(no services linked)"
```

- [ ] **Step 3: `subcommands/app-links` (alias of links for symmetry)**

```bash
#!/usr/bin/env bash
set -eo pipefail
PLUGIN_BASE_PATH="$(cd "$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")" && pwd)"
exec "$PLUGIN_BASE_PATH/subcommands/links" "$@"
```

- [ ] **Step 4: Tests**

`tests/service_linked.bats`:
```bash
#!/usr/bin/env bats
load test_helper

setup() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testpg 2>/dev/null || true
  dokku apps:destroy --force testapp 2>/dev/null || true
  dokku "$PLUGIN_COMMAND_PREFIX:create" testpg redis:7-alpine --port 6379
  dokku apps:create testapp
}

teardown() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testpg 2>/dev/null || true
  dokku apps:destroy --force testapp 2>/dev/null || true
}

@test "(generic:linked) shows none initially" {
  run dokku "$PLUGIN_COMMAND_PREFIX:linked" testpg
  assert_contains "$output" "no apps linked"
}

@test "(generic:linked) shows linked app" {
  dokku "$PLUGIN_COMMAND_PREFIX:link" testpg testapp
  run dokku "$PLUGIN_COMMAND_PREFIX:linked" testpg
  assert_output "testapp"
}
```

`tests/service_links.bats`:
```bash
#!/usr/bin/env bats
load test_helper

setup() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testpg 2>/dev/null || true
  dokku apps:destroy --force testapp 2>/dev/null || true
  dokku "$PLUGIN_COMMAND_PREFIX:create" testpg redis:7-alpine --port 6379
  dokku apps:create testapp
}

teardown() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testpg 2>/dev/null || true
  dokku apps:destroy --force testapp 2>/dev/null || true
}

@test "(generic:links) lists services linked to app" {
  dokku "$PLUGIN_COMMAND_PREFIX:link" testpg testapp
  run dokku "$PLUGIN_COMMAND_PREFIX:links" testapp
  assert_output "testpg"
}
```

`tests/service_app-links.bats`:
```bash
#!/usr/bin/env bats
load test_helper

@test "(generic:app-links) is alias of links" {
  run dokku "$PLUGIN_COMMAND_PREFIX:app-links" nonexistent
  assert_contains "$output" "no services linked"
}
```

- [ ] **Step 5: commit**

```bash
chmod +x subcommands/linked subcommands/links subcommands/app-links
git add subcommands/linked subcommands/links subcommands/app-links tests/service_linked.bats tests/service_links.bats tests/service_app-links.bats commands
git commit -m "feat: linked, links, app-links subcommands"
```

---

## Task 5: `subcommands/promote`

**Goal:** Когда у app есть несколько одинаковых линков (`PG`, `PG2`), `promote` делает указанный сервис primary — переписывает его URL под имя `PG_URL` без суффикса.

**Files:**
- Create: `subcommands/promote`
- Create: `tests/service_promote.bats`

- [ ] **Step 1: Tests**

```bash
#!/usr/bin/env bats

load test_helper

setup() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" pg 2>/dev/null || true
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" pg2 2>/dev/null || true
  dokku apps:destroy --force testapp 2>/dev/null || true
  dokku "$PLUGIN_COMMAND_PREFIX:create" pg redis:7-alpine --port 6379 --scheme redis
  dokku "$PLUGIN_COMMAND_PREFIX:create" pg2 redis:7-alpine --port 6379 --scheme redis
  dokku apps:create testapp
  dokku "$PLUGIN_COMMAND_PREFIX:link" pg testapp
  dokku "$PLUGIN_COMMAND_PREFIX:link" pg2 testapp --alias PG
}

teardown() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" pg 2>/dev/null || true
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" pg2 2>/dev/null || true
  dokku apps:destroy --force testapp 2>/dev/null || true
}

@test "(generic:promote) promotes secondary alias to primary" {
  # initial state: pg → PG_URL, pg2 → PG2_URL
  run dokku config:get testapp PG_URL
  assert_contains "$output" "dokku.generic.pg:6379"
  run dokku config:get testapp PG2_URL
  assert_contains "$output" "dokku.generic.pg2:6379"

  dokku "$PLUGIN_COMMAND_PREFIX:promote" pg2 testapp

  # after promote: pg2 → PG_URL, pg → PG2_URL
  run dokku config:get testapp PG_URL
  assert_contains "$output" "dokku.generic.pg2:6379"
  run dokku config:get testapp PG2_URL
  assert_contains "$output" "dokku.generic.pg:6379"
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
APP="${2:-}"

[[ -z "$SERVICE" ]] && dokku_log_fail "Please specify a service"
[[ -z "$APP"     ]] && dokku_log_fail "Please specify an app"
verify_service_name "$SERVICE" || dokku_log_fail "Invalid service name"
service_exists "$SERVICE" || dokku_log_fail "Service $SERVICE does not exist"

DNS="$(service_container_name "$SERVICE")"
BASE_ALIAS="$(service_alias "$SERVICE")"

# Find current alias of this service in app config (search by URL value)
declare -a CURRENT_KEYS=()
for k in $(dokku config:export --format=envfile "$APP" | grep -oE '^[A-Z_][A-Z0-9_]*'); do
  v=$(dokku config:get --no-restart "$APP" "$k" 2>/dev/null || true)
  if [[ "$v" == *"$DNS"* ]]; then
    CURRENT_KEYS+=("$k")
  fi
done

if [[ ${#CURRENT_KEYS[@]} -eq 0 ]]; then
  dokku_log_fail "Service $SERVICE is not linked to $APP"
fi

# Find the primary occupant of <BASE_ALIAS>_URL (so we can swap)
PRIMARY_URL=$(dokku config:get --no-restart "$APP" "${BASE_ALIAS}_URL" 2>/dev/null || true)

if [[ -n "$PRIMARY_URL" && "$PRIMARY_URL" != *"$DNS"* ]]; then
  # Find the service that currently holds primary
  OTHER_DNS=$(echo "$PRIMARY_URL" | sed -E 's|^[^:]+://([^:/]+).*|\1|')
  OTHER_SVC="${OTHER_DNS#dokku.generic.}"

  # Compute next alternative
  ALT_ALIAS="$(service_alternative_alias "$APP" "$BASE_ALIAS")"

  # Move other svc to alternative alias
  declare -a NEW_PAIRS=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    k="${line%%=*}"; v="${line#*=}"
    if [[ "$k" == "${BASE_ALIAS}_HOST" || "$k" == "${BASE_ALIAS}_PORT" || "$k" == "${BASE_ALIAS}_URL" ]]; then
      new_k="${ALT_ALIAS}${k#${BASE_ALIAS}}"
      NEW_PAIRS+=("$new_k=$v")
      dokku config:unset --no-restart "$APP" "$k" >/dev/null 2>&1 || true
    fi
  done < <(dokku config:export --format=envfile "$APP")
  if [[ ${#NEW_PAIRS[@]} -gt 0 ]]; then
    dokku config:set --no-restart "$APP" "${NEW_PAIRS[@]}"
  fi
fi

# Now move our service to primary alias
declare -a OUR_PAIRS=()
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  k="${line%%=*}"; v="${line#*=}"
  if [[ "$v" == *"$DNS"* || "$k" == "*_HOST" && "$v" == "$DNS" ]]; then
    # extract suffix (HOST/PORT/URL)
    suffix="${k##*_}"
    OUR_PAIRS+=("${BASE_ALIAS}_${suffix}=$v")
    dokku config:unset --no-restart "$APP" "$k" >/dev/null 2>&1 || true
  fi
done < <(dokku config:export --format=envfile "$APP")

if [[ ${#OUR_PAIRS[@]} -gt 0 ]]; then
  dokku config:set "$APP" "${OUR_PAIRS[@]}"
fi

dokku_log_info2 "Promoted $SERVICE to primary for $APP"
```

- [ ] **Step 3: commit**

```bash
chmod +x subcommands/promote
docker exec dokku-generic-test bats /var/lib/dokku/plugins/available/generic/tests/service_promote.bats
git add subcommands/promote tests/service_promote.bats commands
git commit -m "feat: subcommands/promote — alias swap"
```

---

## Task 6: `tests/link_networks.bats` — изоляция сетей

**Files:**
- Create: `tests/link_networks.bats`

- [ ] **Step 1: Tests**

```bash
#!/usr/bin/env bats

load test_helper

setup() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" svc1 2>/dev/null || true
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" svc2 2>/dev/null || true
  dokku apps:destroy --force app1 2>/dev/null || true
  dokku apps:destroy --force app2 2>/dev/null || true
  dokku "$PLUGIN_COMMAND_PREFIX:create" svc1 redis:7-alpine --port 6379
  dokku "$PLUGIN_COMMAND_PREFIX:create" svc2 redis:7-alpine --port 6379
  dokku apps:create app1
  dokku apps:create app2
  dokku "$PLUGIN_COMMAND_PREFIX:link" svc1 app1
  dokku "$PLUGIN_COMMAND_PREFIX:link" svc2 app2
}

teardown() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" svc1 2>/dev/null || true
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" svc2 2>/dev/null || true
  dokku apps:destroy --force app1 2>/dev/null || true
  dokku apps:destroy --force app2 2>/dev/null || true
}

@test "isolation: app1 only has svc1's network in docker-options" {
  run dokku docker-options:report app1
  assert_contains "$output" "--network=dokku.generic.svc1"
  assert_not_contains "$output" "--network=dokku.generic.svc2"
}

@test "isolation: app2 only has svc2's network in docker-options" {
  run dokku docker-options:report app2
  assert_contains "$output" "--network=dokku.generic.svc2"
  assert_not_contains "$output" "--network=dokku.generic.svc1"
}

@test "isolation: svc1 and svc2 networks are different" {
  net1=$(docker network inspect -f '{{.Id}}' dokku.generic.svc1)
  net2=$(docker network inspect -f '{{.Id}}' dokku.generic.svc2)
  [[ "$net1" != "$net2" ]]
}
```

- [ ] **Step 2: commit**

```bash
docker exec dokku-generic-test bats /var/lib/dokku/plugins/available/generic/tests/link_networks.bats
git add tests/link_networks.bats
git commit -m "test: link network isolation between services"
```

---

## Self-Review

Coverage §3.5: link/unlink/linked/links/app-links/promote — все есть. `service_alternative_alias` решает alias-конфликт. Изоляция сетей покрыта `link_networks.bats`. Limitation: `unlink` ищет конфиг-ключи по совпадению значения с DNS-именем сервиса (а не по сохранённому alias), потому что мы alias не запоминаем. Если значение `LINK_ENV` не содержит DNS-имени сервиса, его уберёт явный `LINK_ENV` reverse-pass. Это допустимый trade-off; если вылезет в smoke — добавить `ALIAS` файл в state, пишем при link, читаем при unlink.
