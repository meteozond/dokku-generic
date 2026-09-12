#!/usr/bin/env bats

load test_helper

@test "(generic:app-links) rejects nonexistent app (alias of links)" {
  run dokku "$PLUGIN_COMMAND_PREFIX:app-links" nonexistent
  assert_failure
  assert_contains "$output" "does not exist"
}

@test "(generic:app-links) lists services linked to existing app with no links" {
  dokku apps:destroy --force applink-noent 2>/dev/null || true
  dokku apps:create applink-noent
  run dokku "$PLUGIN_COMMAND_PREFIX:app-links" applink-noent
  assert_success
  assert_contains "$output" "no services linked"
  dokku apps:destroy --force applink-noent
}
