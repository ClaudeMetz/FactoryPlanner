#!/bin/bash
set -e

FACTORIO=${FACTORIO:-/opt/factorio/bin/x64/factorio}
WORKSPACE=${GITHUB_WORKSPACE:-.}
TEST=${1:-save-create}

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

run_tests() {
  local name=$1
  cp -r $WORKSPACE/tests/$name $TMPDIR/mods/tests-$name
  $FACTORIO --mod-directory $TMPDIR/mods --create $TMPDIR/$name-map.zip 2>&1 | tee $TMPDIR/factorio.log
  if [ ${PIPESTATUS[0]} -ne 0 ] || grep -q "Error" $TMPDIR/factorio.log; then
    echo "Mod error during test run"
    exit 1
  fi
  if ! grep -q "tests_passed\|tests_failed" $TMPDIR/factorio.log; then
    echo "Tests did not run"
    exit 1
  fi
  if grep -q "tests_failed\|setup_failed" $TMPDIR/factorio.log; then
    echo "Not all tests passed"
    exit 1
  fi
}

mkdir -p $TMPDIR/mods
cp -r $WORKSPACE/modfiles $TMPDIR/mods/factoryplanner

case $TEST in
  save-create)
    $FACTORIO --mod-directory $TMPDIR/mods --create $TMPDIR/test-map.zip 2>&1 | tee $TMPDIR/factorio.log
    if [ ${PIPESTATUS[0]} -ne 0 ] || grep -q "Error" $TMPDIR/factorio.log; then
      exit 1
    fi
    ;;
  generator) run_tests generator ;;
  runtime)   run_tests runtime   ;;
esac
