#!/usr/bin/env bats

load test_helper

teardown() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testcreate 2>/dev/null || true
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" service-with-dashes 2>/dev/null || true
}

@test "(generic:create) success with image" {
  run dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate redis:7-alpine
  assert_success
  assert_contains "$output" "container created: testcreate"
}

@test "(generic:create) records image in state" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate redis:7-alpine
  run cat "$PLUGIN_DATA_HOST_ROOT/testcreate/IMAGE"
  assert_output "redis:7-alpine"
}

@test "(generic:create) creates docker network" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate redis:7-alpine
  run docker network inspect "dokku-generic-testcreate"
  assert_success
}

@test "(generic:create) starts running container" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate redis:7-alpine
  run docker container inspect -f '{{.State.Status}}' "dokku-generic-testcreate"
  assert_output "running"
}

@test "(generic:create) accepts service name with dashes" {
  run dokku "$PLUGIN_COMMAND_PREFIX:create" service-with-dashes redis:7-alpine
  assert_success
  assert_contains "$output" "container created: service-with-dashes"
}

@test "(generic:create) error when no name" {
  run dokku "$PLUGIN_COMMAND_PREFIX:create"
  assert_failure
  assert_contains "$output" "Please specify a valid name"
}

@test "(generic:create) error when no image" {
  run dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate
  assert_failure
  assert_contains "$output" "Please specify a docker image"
}

@test "(generic:create) error when name has dot" {
  run dokku "$PLUGIN_COMMAND_PREFIX:create" "bad.name" redis:7-alpine
  assert_failure
}

@test "(generic:create) error when service already exists" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate redis:7-alpine
  run dokku "$PLUGIN_COMMAND_PREFIX:create" testcreate redis:7-alpine
  assert_failure
  assert_contains "$output" "already exists"
}
