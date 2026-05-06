#!/usr/bin/env bats

load test_helper

teardown() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testdestroy 2>/dev/null || true
}

@test "(generic:destroy) success with --force" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testdestroy redis:7-alpine
  run dokku "$PLUGIN_COMMAND_PREFIX:destroy" testdestroy --force
  assert_success
  run docker container inspect "dokku-generic-testdestroy"
  assert_failure
}

@test "(generic:destroy) removes state directory" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testdestroy redis:7-alpine
  dokku "$PLUGIN_COMMAND_PREFIX:destroy" testdestroy --force
  [[ ! -d "$PLUGIN_DATA_HOST_ROOT/testdestroy" ]]
}

@test "(generic:destroy) removes docker network" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testdestroy redis:7-alpine
  dokku "$PLUGIN_COMMAND_PREFIX:destroy" testdestroy --force
  run docker network inspect "dokku-generic-testdestroy"
  assert_failure
}

@test "(generic:destroy) removes default named volume" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testdestroy redis:7-alpine --no-start --mount /data
  dokku "$PLUGIN_COMMAND_PREFIX:destroy" testdestroy --force
  # Default and per-mount volumes should be gone
  run docker volume ls --format '{{.Name}}'
  assert_not_contains "$output" "dokku.generic.testdestroy"
}

@test "(generic:destroy) error when not exists" {
  run dokku "$PLUGIN_COMMAND_PREFIX:destroy" doesnotexist --force
  assert_failure
  assert_contains "$output" "does not exist"
}

@test "(generic:destroy) error when no name" {
  run dokku "$PLUGIN_COMMAND_PREFIX:destroy"
  assert_failure
}

@test "(generic:destroy) confirms via service name when no --force" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testdestroy redis:7-alpine
  run bash -c "echo 'wrongname' | dokku '$PLUGIN_COMMAND_PREFIX:destroy' testdestroy"
  assert_failure
  assert_contains "$output" "Confirmation did not match"
}

@test "(generic:destroy) succeeds when correct name typed" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testdestroy redis:7-alpine
  run bash -c "echo 'testdestroy' | dokku '$PLUGIN_COMMAND_PREFIX:destroy' testdestroy"
  assert_success
}
