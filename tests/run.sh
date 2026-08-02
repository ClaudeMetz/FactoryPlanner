#!/bin/bash
set -e

FACTORIO=${FACTORIO:-/opt/factorio/bin/x64/factorio}
WORKSPACE=${GITHUB_WORKSPACE:-.}
TEST=${1:-save-create}

# The mod targets the experimental branch, so track 'latest' rather than 'stable'
DOWNLOAD=https://factorio.com/get-download/latest/headless/linux64

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

installed_version() {
  $FACTORIO --version 2>/dev/null | sed -n '1s/^Version: \([0-9][0-9.]*\).*/\1/p'
}

# Never fatal: a failed update leaves the existing install in place and tests run on it
update_factorio() {
  local root=${FACTORIO%/bin/x64/factorio}
  [ "$root" = "$FACTORIO" ] && return 0

  local url latest current
  url=$(curl -sIL -o /dev/null -w '%{url_effective}' --max-time 30 $DOWNLOAD) || url=""
  latest=$(printf '%s' "$url" | sed -n 's/.*_\([0-9][0-9.]*\)\.tar\.xz.*/\1/p')
  current=$(installed_version)

  if [ -z "$latest" ] || [ -z "$current" ]; then
    echo "WARNING: update check failed, using installed Factorio"
    return 0
  elif [ "$latest" = "$current" ]; then
    echo "Factorio $current is up to date"
    return 0
  fi

  echo "Updating Factorio $current -> $latest"
  if ! curl -sfL --max-time 600 "$url" -o $TMPDIR/headless.tar.xz; then
    echo "WARNING: download of Factorio $latest failed, using $current"
  elif ! tar -xJf $TMPDIR/headless.tar.xz -C $(dirname $root); then
    echo "WARNING: extraction failed, check write access to $root; using $current"
  else
    echo "Factorio updated to $(installed_version)"
  fi
  return 0
}

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

update_factorio

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
