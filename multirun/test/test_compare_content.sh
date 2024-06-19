#!/usr/bin/env bash

# Test harness.  Runs the command `$1`, checking that it exits with code `$2` and its stdout output matches the content
# of `$3`.  Exits 0 if all is matching, non-0 otherwise.

set -o pipefail

# Use `eval` instead of just `$($1)` to allow the command to include
# pipelines.
# tolerate CRLF vs LF differences. 
# Golang always writes LF for \n, other languges write CRLF windows.
ACTUAL_OUT=$(eval "$1" 2>&1 | dos2unix)
ACTUAL_CODE=$?
EXPECTED_CODE=$2
EXPECTED_OUT=$(cat "$3" | dos2unix) 

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
    /c/apps/bazel/git/usr/bin/diff.exe --label="< expected" --label="> actual"s `pwd`/$3 `pwd`/actual.txt | cat -t
    exit 1
fi
