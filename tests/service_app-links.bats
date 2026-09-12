#!/usr/bin/env bats

load test_helper

@test "(generic:app-links) rejects nonexistent app (alias of links)" {
  run dokku "$PLUGIN_COMMAND_PREFIX:app-links" nonexistent
  assert_failure
  assert_contains "$output" "does not exist"
}

@test "(generic:app-links) lists services linked to existing app with no links" {
  dokku apps:destroy --force applink-noent 2>/dev/null || true
  # Dokku 0.38 triggers an nginx reload from apps:create that can exit nonzero
  # ("No web listeners specified"); the app is still created. We only need it
  # to exist for the test — verify via apps:exists rather than relying on
  # apps:create's exit status.
  dokku apps:create applink-noent >/dev/null 2>&1 || true
  dokku apps:exists applink-noent || flunk "apps:create did not produce the app"
  run dokku "$PLUGIN_COMMAND_PREFIX:app-links" applink-noent
  assert_success
  assert_contains "$output" "no services linked"
  dokku apps:destroy --force applink-noent
}
