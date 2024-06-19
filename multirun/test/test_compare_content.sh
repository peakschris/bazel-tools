#!/usr/bin/env bash

# Test harness.  Runs the command `$1`, checking that it exits with code `$2` and its stdout output matches the content
# of `$3`.  Exits 0 if all is matching, non-0 otherwise.

set -o pipefail

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

#echo test_compare_content argv[0]=$1 argv[1]=$2 argv[2]=$3
#if [[ -v RUNFILES_MANIFEST_FILE ]]; then
#    echo RUNFILES_MANIFEST_FILE=$RUNFILES_MANIFEST_FILE
#fi
#if [[ -v RUNFILES_DIR ]]; then
#    echo RUNFILES_DIR=$RUNFILES_DIR
#fi
# Use `eval` instead of just `$($1)` to allow the command to include
# pipelines.
# tolerate CRLF vs LF differences. 
# Golang always writes LF for \n, other languges write CRLF windows.
unquoted=$1
unquoted="${unquoted%\'}"
unquoted="${unquoted#\'}"
cmd=($unquoted)
cmd[0]=$(rlocation ${cmd[0]})
cmd[0]="${cmd[0]//\\//}"
args="'${cmd[@]:1}'"
expected=$(rlocation $3)
expected="${expected//\\//}"
debug=0
if [[ $debug == 1 ]]; then
    echo "cmd=$cmd"
    echo "args=$args"
    echo "expected=$expected"
fi
#echo ACTUAL_OUT="$($cmd ${args[@]})"
ACTUAL_OUT="$($cmd ${args[@]})"
#ACTUAL_OUT="dummy"
#echo ACTUAL_OUT=$ACTUAL_OUT
ACTUAL_CODE=$?
EXPECTED_CODE=$2
EXPECTED_OUT=$(cat "$expected" | dos2unix) 

if [[ "$ACTUAL_OUT" == "$EXPECTED_OUT" ]] && [[ "$ACTUAL_CODE" -eq "$EXPECTED_CODE" ]]
then
    echo "match"
    exit 0
else
    echo "mismatch"
    echo "expected code $EXPECTED_CODE, stdout:"
    echo "$EXPECTED_OUT" | cat -t
    echo
    echo "actual code $ACTUAL_CODE, stdout:"
    echo "$ACTUAL_OUT" | cat -t
    echo "$ACTUAL_OUT" > "actual.txt"
    echo
    echo "diff < expected  > actual"
    /c/apps/bazel/git/usr/bin/diff.exe --label="< expected" --label="> actual"s $expected `pwd`/actual.txt | cat -t
    exit 1
fi
