#!/usr/bin/env bats

load test_helper

@test "(generic:app-links) is alias of links" {
  run dokku "$PLUGIN_COMMAND_PREFIX:app-links" nonexistent
  assert_contains "$output" "no services linked"
}
