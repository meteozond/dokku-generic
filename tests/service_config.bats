#!/usr/bin/env bats

load test_helper

teardown() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testconfig 2>/dev/null || true
}

@test "(generic:config) shows env section" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testconfig redis:7-alpine --env FOO=bar --env BAZ=qux
  run dokku "$PLUGIN_COMMAND_PREFIX:config" testconfig
  assert_success
  assert_contains "$output" "FOO=bar"
  assert_contains "$output" "BAZ=qux"
}

@test "(generic:config) shows link-env section" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testconfig redis:7-alpine --link-env DATABASE_URL=postgres://x
  run dokku "$PLUGIN_COMMAND_PREFIX:config" testconfig
  assert_success
  assert_contains "$output" "DATABASE_URL=postgres://x"
}

@test "(generic:config) shows mounts" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testconfig redis:7-alpine --mount /var/data --mount /host:/container
  run dokku "$PLUGIN_COMMAND_PREFIX:config" testconfig
  assert_success
  assert_contains "$output" "/var/data"
  assert_contains "$output" "/host:/container"
}

@test "(generic:config) shows port and scheme" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testconfig redis:7-alpine --port 6379 --scheme redis
  run dokku "$PLUGIN_COMMAND_PREFIX:config" testconfig
  assert_success
  assert_contains "$output" "6379"
  assert_contains "$output" "redis"
}

@test "(generic:config) error when not exists" {
  run dokku "$PLUGIN_COMMAND_PREFIX:config" missing
  assert_failure
}
