#!/usr/bin/env bash

# Helper script to spawn a command, sleep and then kill it.

# --- begin runfiles.bash initialization v3 ---
# Copy-pasted from the Bazel Bash runfiles library v3.
set -uo pipefail; set +e; f=bazel_tools/tools/bash/runfiles/runfiles.bash
# shellcheck disable=SC1090
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null || \
  source "$0.runfiles/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  { echo>&2 "ERROR: cannot find $f"; exit 1; }; f=; set -e
# --- end runfiles.bash initialization v3 ---

# unquote $1 and split into <command> <sleep> <kill_signal>
echo "run_and_kill $1" >2
if [[ -v RUNFILES_MANIFEST_FILE ]]; then
    echo RUNFILES_MANIFEST_FILE=$RUNFILES_MANIFEST_FILE >2
fi
if [[ -v RUNFILES_DIR ]]; then
    echo RUNFILES_DIR=$RUNFILES_DIR >2
fi
unquoted=$1
unquoted="${unquoted%\'}"
unquoted="${unquoted#\'}"
args=($unquoted)

# name and sanitize args
command=$(rlocation ${args[0]})
command="${command//\\//}"
sleep=${args[1]}
signal=${args[2]}
echo "$command $sleep $signal"

echo "RAK>>running $command"
$command &
pid=$!
echo "RAK>>sleeping $sleep"
sleep "$sleep"
echo "RAK>>killing with signal $signal"
kill -s "$signal" "$pid"
wait "$pid"
echo "RAK>>done"
wait "$pid"
