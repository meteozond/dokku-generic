#!/usr/bin/env bash

export PLUGIN_COMMAND_PREFIX="generic"
export PLUGIN_SERVICE="generic"
export PLUGIN_DATA_HOST_ROOT="/var/lib/dokku/services/generic"
export PLUGIN_BASE_PATH="${PLUGIN_BASE_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export PLUGIN_NETWORK_PREFIX="dokku-generic"
export PLUGIN_CONTAINER_PREFIX="dokku-generic"
export PLUGIN_VOLUME_PREFIX="dokku.generic"

flunk() {
  { if [ "$#" -eq 0 ]; then cat -; else echo "$@"; fi; } | sed "s:${TMPDIR}:\$TMPDIR/:g" >&2
  return 1
}

assert_equal() {
  if [ "$1" != "$2" ]; then
    {
      echo "expected: $1"
      echo "actual:   $2"
    } | flunk
  fi
}

assert_contains() {
  if [[ "$1" != *"$2"* ]]; then
    {
      echo "expected to contain: $2"
      echo "actual:              $1"
    } | flunk
  fi
}

assert_not_contains() {
  if [[ "$1" == *"$2"* ]]; then
    {
      echo "expected NOT to contain: $2"
      echo "actual:                  $1"
    } | flunk
  fi
}

assert_success() {
  if [ "$status" -ne 0 ]; then
    flunk "command failed with exit status $status: $output"
  fi
}

assert_failure() {
  if [ "$status" -eq 0 ]; then
    flunk "expected failed exit status, got 0: $output"
  fi
  if [ "$#" -gt 0 ]; then
    assert_contains "$output" "$1"
  fi
}

assert_output() {
  local expected="$1"
  if [ "$expected" != "$output" ]; then
    {
      echo "expected: $expected"
      echo "actual:   $output"
    } | flunk
  fi
}

source_plugin() {
  source "$PLUGIN_BASE_PATH/config"
  source "$PLUGIN_BASE_PATH/common-functions"
  source "$PLUGIN_BASE_PATH/functions"
}
