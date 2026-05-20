#!/bin/bash
set -e

FACTORIO=${FACTORIO:-/opt/factorio/bin/x64/factorio}
WORKSPACE=${GITHUB_WORKSPACE:-.}
TEST=${1:-save-create}

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

mkdir -p $TMPDIR/mods
cp -r $WORKSPACE/modfiles $TMPDIR/mods/factoryplanner
git clone --depth 1 --branch v0.16.5 https://codeberg.org/raiguard/flib $TMPDIR/mods/flib

case $TEST in
  save-create)
    $FACTORIO --mod-directory $TMPDIR/mods --create $TMPDIR/test-map.zip 2>&1 | tee $TMPDIR/factorio.log
    if [ ${PIPESTATUS[0]} -ne 0 ] || grep -q "Error" $TMPDIR/factorio.log; then
      exit 1
    fi
    ;;
  generator)
    cp -r $WORKSPACE/tests/generator $TMPDIR/mods/tests-generator
    $FACTORIO --mod-directory $TMPDIR/mods --load-scenario freeplay > $TMPDIR/factorio.log 2>&1 &
    FACTORIO_PID=$!

    TIMEOUT=60
    until grep -q "Tests completed" $TMPDIR/factorio.log 2>/dev/null || [ $TIMEOUT -eq 0 ]; do
      sleep 1
      TIMEOUT=$((TIMEOUT - 1))
    done

    kill $FACTORIO_PID 2>/dev/null || true
    wait $FACTORIO_PID 2>/dev/null || true
    cat $TMPDIR/factorio.log

    if ! grep -q "Tests completed" $TMPDIR/factorio.log; then
      echo "Generator tests did not complete within timeout"
      exit 1
    fi
    if grep -q "Error" $TMPDIR/factorio.log; then
      exit 1
    fi
    ;;
esac
