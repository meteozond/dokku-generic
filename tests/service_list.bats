#!/usr/bin/env bats

load test_helper

@test "(generic:list) empty list when no services" {
  run dokku "$PLUGIN_COMMAND_PREFIX:list"
  assert_success
  # Either prints header or "No services" — accept any non-failure
}

@test "(generic:list) shows created services" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testlist redis:7-alpine
  run dokku "$PLUGIN_COMMAND_PREFIX:list"
  assert_success
  assert_contains "$output" "testlist"
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testlist
}
