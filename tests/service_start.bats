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
