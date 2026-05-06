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

  count=$(docker container ls -aq --filter "label=dokku.ambassador.service=testexp" | wc -l | tr -d ' ')
  [[ "$count" -eq 0 ]] || flunk "expected 0 ambassadors, got $count"
}

@test "(generic:unexpose) error when port not exposed" {
  run dokku "$PLUGIN_COMMAND_PREFIX:unexpose" testexp 99999:9999
  assert_failure
}
