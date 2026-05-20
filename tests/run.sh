#!/bin/bash
set -e

FACTORIO=${FACTORIO:-/opt/factorio/bin/x64/factorio}
WORKSPACE=${GITHUB_WORKSPACE:-.}

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

mkdir -p $TMPDIR/mods
cp -r $WORKSPACE/modfiles $TMPDIR/mods/factoryplanner
git clone --depth 1 --branch v0.16.5 https://codeberg.org/raiguard/flib $TMPDIR/mods/flib

$FACTORIO \
  --mod-directory $TMPDIR/mods \
  --create $TMPDIR/test-map.zip \
  2>&1 | tee $TMPDIR/factorio.log
if [ ${PIPESTATUS[0]} -ne 0 ] || grep -q "Error" $TMPDIR/factorio.log; then
  exit 1
fi
