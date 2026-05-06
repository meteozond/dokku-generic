#!/usr/bin/env bats
load test_helper

setup() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testpause 2>/dev/null || true
  dokku "$PLUGIN_COMMAND_PREFIX:create" testpause redis:7-alpine
}

teardown() {
  docker container unpause dokku-generic-testpause 2>/dev/null || true
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testpause 2>/dev/null || true
}

@test "(generic:pause) pauses running container" {
  run dokku "$PLUGIN_COMMAND_PREFIX:pause" testpause
  assert_success
  run docker container inspect -f '{{.State.Status}}' dokku-generic-testpause
  assert_output "paused"
}

@test "(generic:pause) unpauses paused container (toggle)" {
  dokku "$PLUGIN_COMMAND_PREFIX:pause" testpause
  run dokku "$PLUGIN_COMMAND_PREFIX:pause" testpause
  assert_success
  run docker container inspect -f '{{.State.Status}}' dokku-generic-testpause
  assert_output "running"
}
