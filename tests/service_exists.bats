#!/usr/bin/env bats

load test_helper

@test "(generic:exists) exit 1 when missing" {
  run dokku "$PLUGIN_COMMAND_PREFIX:exists" doesnotexist
  assert_failure
}

@test "(generic:exists) exit 0 when present" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testexist redis:7-alpine
  run dokku "$PLUGIN_COMMAND_PREFIX:exists" testexist
  assert_success
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testexist
}
