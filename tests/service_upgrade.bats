#!/usr/bin/env bats

load test_helper

setup() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testupgrade 2>/dev/null || true
  dokku "$PLUGIN_COMMAND_PREFIX:create" testupgrade redis:7-alpine
}

teardown() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testupgrade 2>/dev/null || true
}

@test "(generic:upgrade) updates image and restarts" {
  run dokku "$PLUGIN_COMMAND_PREFIX:upgrade" testupgrade redis:7
  assert_success
  run cat "$PLUGIN_DATA_HOST_ROOT/testupgrade/IMAGE"
  assert_output "redis:7"
  run docker container inspect -f '{{.Config.Image}}' "dokku-generic-testupgrade"
  assert_output "redis:7"
}

@test "(generic:upgrade) error when service missing" {
  run dokku "$PLUGIN_COMMAND_PREFIX:upgrade" missing redis:7
  assert_failure
}

@test "(generic:upgrade) error when no image" {
  run dokku "$PLUGIN_COMMAND_PREFIX:upgrade" testupgrade
  assert_failure
}
