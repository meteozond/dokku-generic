#!/usr/bin/env bats

load test_helper

setup() {
  rm -f "$PLUGIN_DATA_HOST_ROOT/pg/LINKS" 2>/dev/null || true
  rm -f "$PLUGIN_DATA_HOST_ROOT/pg2/LINKS" 2>/dev/null || true
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
  rm -f "$PLUGIN_DATA_HOST_ROOT/pg/LINKS" 2>/dev/null || true
  rm -f "$PLUGIN_DATA_HOST_ROOT/pg2/LINKS" 2>/dev/null || true
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
