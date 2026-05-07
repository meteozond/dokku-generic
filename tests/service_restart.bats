#!/usr/bin/env bats
load test_helper

setup() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testrestart 2>/dev/null || true
  dokku "$PLUGIN_COMMAND_PREFIX:create" testrestart redis:7-alpine
}

teardown() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testrestart 2>/dev/null || true
}

@test "(generic:restart) recreates container with current state" {
  initial_id=$(docker container inspect -f '{{.Id}}' dokku.generic.testrestart)
  run dokku "$PLUGIN_COMMAND_PREFIX:restart" testrestart
  assert_success
  new_id=$(docker container inspect -f '{{.Id}}' dokku.generic.testrestart)
  [[ "$initial_id" != "$new_id" ]]
}

@test "(generic:restart) error when missing" {
  run dokku "$PLUGIN_COMMAND_PREFIX:restart" missing
  assert_failure
}
