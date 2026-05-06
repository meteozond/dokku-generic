#!/usr/bin/env bats
load test_helper

setup() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testlogs 2>/dev/null || true
  dokku "$PLUGIN_COMMAND_PREFIX:create" testlogs redis:7-alpine
  sleep 2  # let some logs accumulate
}

teardown() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testlogs 2>/dev/null || true
}

@test "(generic:logs) shows container logs" {
  run dokku "$PLUGIN_COMMAND_PREFIX:logs" testlogs
  assert_success
  assert_contains "$output" "Ready to accept connections"
}

@test "(generic:logs -t) shows logs with timestamps" {
  run dokku "$PLUGIN_COMMAND_PREFIX:logs" testlogs -t
  assert_success
  # ISO timestamps look like 2026-...
  [[ "$output" =~ 20[0-9]{2}- ]]
}

@test "(generic:logs -n N) shows last N lines" {
  run dokku "$PLUGIN_COMMAND_PREFIX:logs" testlogs -n 1
  assert_success
  # exactly one line (or fewer)
  lines=$(echo "$output" | wc -l)
  [[ "$lines" -le 2 ]]
}
