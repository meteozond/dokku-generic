#!/usr/bin/env bats

load test_helper

teardown() {
  dokku --force "$PLUGIN_COMMAND_PREFIX:destroy" testinfo 2>/dev/null || true
}

@test "(generic:info) shows image" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testinfo redis:7-alpine
  run dokku "$PLUGIN_COMMAND_PREFIX:info" testinfo
  assert_success
  assert_contains "$output" "Image:"
  assert_contains "$output" "redis:7-alpine"
}

@test "(generic:info) shows status running after create" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testinfo redis:7-alpine
  run dokku "$PLUGIN_COMMAND_PREFIX:info" testinfo
  assert_success
  assert_contains "$output" "Status:"
  assert_contains "$output" "running"
}

@test "(generic:info) shows status created after --no-start" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testinfo redis:7-alpine --no-start
  run dokku "$PLUGIN_COMMAND_PREFIX:info" testinfo
  assert_success
  assert_contains "$output" "created"
}

@test "(generic:info) shows port when set" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testinfo redis:7-alpine --port 6379
  run dokku "$PLUGIN_COMMAND_PREFIX:info" testinfo
  assert_success
  assert_contains "$output" "Port:"
  assert_contains "$output" "6379"
}

@test "(generic:info --image) prints only image" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testinfo redis:7-alpine
  run dokku "$PLUGIN_COMMAND_PREFIX:info" testinfo --image
  assert_success
  assert_output "redis:7-alpine"
}

@test "(generic:info --status) prints only status" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testinfo redis:7-alpine
  run dokku "$PLUGIN_COMMAND_PREFIX:info" testinfo --status
  assert_success
  assert_output "running"
}

@test "(generic:info --internal-ip) prints container IP in service network" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testinfo redis:7-alpine
  run dokku "$PLUGIN_COMMAND_PREFIX:info" testinfo --internal-ip
  assert_success
  [[ "$output" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || flunk "expected IP, got $output"
}

@test "(generic:info) error when not exists" {
  run dokku "$PLUGIN_COMMAND_PREFIX:info" missing
  assert_failure
}

@test "(generic:info --docker-args) prints docker args" {
  dokku "$PLUGIN_COMMAND_PREFIX:create" testinfo redis:7-alpine --docker-arg=--memory=128m
  run dokku "$PLUGIN_COMMAND_PREFIX:info" testinfo --docker-args
  assert_success
  assert_contains "$output" "--memory=128m"
}
