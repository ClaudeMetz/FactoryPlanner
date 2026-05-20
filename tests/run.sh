#!/bin/bash
set -e

FACTORIO=${FACTORIO:-/opt/factorio/bin/x64/factorio}
WORKSPACE=${GITHUB_WORKSPACE:-.}
TEST=${1:-save-create}

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

mkdir -p $TMPDIR/mods
cp -r $WORKSPACE/modfiles $TMPDIR/mods/factoryplanner
git clone -q --depth 1 --branch v0.16.5 https://codeberg.org/raiguard/flib $TMPDIR/mods/flib

case $TEST in
  save-create)
    $FACTORIO --mod-directory $TMPDIR/mods --create $TMPDIR/test-map.zip 2>&1 | tee $TMPDIR/factorio.log
    if [ ${PIPESTATUS[0]} -ne 0 ] || grep -q "Error" $TMPDIR/factorio.log; then
      exit 1
    fi
    ;;
  generator)
    cp -r $WORKSPACE/tests/generator $TMPDIR/mods/tests-generator
    $FACTORIO --mod-directory $TMPDIR/mods --create $TMPDIR/generator-map.zip 2>&1 | tee $TMPDIR/factorio.log
    if [ ${PIPESTATUS[0]} -ne 0 ] || grep -q "Error" $TMPDIR/factorio.log; then
      exit 1
    fi
    if ! grep -q "Tests completed" $TMPDIR/factorio.log; then
      echo "Generator tests did not run"
      exit 1
    fi
    ;;
esac
