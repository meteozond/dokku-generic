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
