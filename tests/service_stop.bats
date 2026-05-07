#!/usr/bin/env bats
load test_helper

setup() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" teststop 2>/dev/null || true
  dokku "$PLUGIN_COMMAND_PREFIX:create" teststop redis:7-alpine
}

teardown() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" teststop 2>/dev/null || true
}

@test "(generic:stop) stops a running service" {
  run dokku "$PLUGIN_COMMAND_PREFIX:stop" teststop
  assert_success
  run docker container inspect -f '{{.State.Status}}' dokku.generic.teststop
  assert_output "exited"
}

@test "(generic:stop) is no-op when stopped" {
  docker container stop dokku.generic.teststop
  run dokku "$PLUGIN_COMMAND_PREFIX:stop" teststop
  assert_success
}
