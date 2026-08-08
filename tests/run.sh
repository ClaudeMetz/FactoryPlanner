#!/bin/bash
set -e

FACTORIO=${FACTORIO:-/opt/factorio/bin/x64/factorio}
WORKSPACE=${GITHUB_WORKSPACE:-.}
TEST=${1:-save-create}
WORLD=${2:-}

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

# Runs a single world: a fresh mod directory, then one map creation with the test mod active
run_world() {
  local world_file=$1
  local world=$(basename $world_file .lua)
  local mods=$TMPDIR/mods-$world
  local logfile=$TMPDIR/$world.log

  mkdir -p $mods
  cp -r $WORKSPACE/modfiles $mods/factoryplanner
  cp -r $WORKSPACE/tests/mod $mods/factoryplanner-test
  # The active world is baked into the test mod copy at a canonical path
  cp $world_file $mods/factoryplanner-test/world.lua

  # Whether the base game is enabled is encoded in the world file's parent directory
  local base_enabled=false
  [ "$(basename $(dirname $world_file))" = "base" ] && base_enabled=true

  if [ $base_enabled = true ]; then
    # The replacement freeplay scenario is only for no-base runs; base brings its own
    rm -r $mods/factoryplanner-test/scenarios
  else
    # The shipped dependency on base is relaxed so that it can be disabled for the test run
    sed -i.bak 's/"base >= /"? base >= /' $mods/factoryplanner/info.json
    rm $mods/factoryplanner/info.json.bak
  fi

  # Pin the full mod set so runs don't depend on the installation's defaults
  cat > $mods/mod-list.json << EOF
{
    "mods": [
        { "name": "base", "enabled": $base_enabled },
        { "name": "space-age", "enabled": false },
        { "name": "quality", "enabled": false },
        { "name": "elevated-rails", "enabled": false },
        { "name": "factoryplanner", "enabled": true },
        { "name": "factoryplanner-test", "enabled": true }
    ]
}
EOF

  local exit_code=0
  $FACTORIO --mod-directory $mods --create $TMPDIR/$world-map.zip > $logfile 2>&1 || exit_code=$?
  sed "s/^/[$world] /" $logfile

  if [ $exit_code -ne 0 ] || grep -q "Error" $logfile; then
    echo "[$world] Mod error during test run"
    return 1
  elif ! grep -q "tests_passed\|tests_failed" $logfile; then
    echo "[$world] Tests did not run"
    return 1
  elif grep -q "tests_failed\|setup_failed" $logfile; then
    echo "[$world] Not all tests passed"
    return 1
  fi
  echo "[$world] All tests passed"
}

# Runs every world in sequence, reporting all failures rather than stopping at the first
run_worlds() {
  local failed=""
  for world_file in $WORKSPACE/tests/worlds/*/*.lua; do
    run_world $world_file || failed="$failed $(basename $world_file .lua)"
  done

  if [ -n "$failed" ]; then
    echo "Failed worlds:$failed"
    exit 1
  fi
  echo "All worlds passed"
}

update_factorio

case $TEST in
  save-create)
    mkdir -p $TMPDIR/mods
    cp -r $WORKSPACE/modfiles $TMPDIR/mods/factoryplanner
    $FACTORIO --mod-directory $TMPDIR/mods --create $TMPDIR/test-map.zip 2>&1 | tee $TMPDIR/factorio.log
    if [ ${PIPESTATUS[0]} -ne 0 ] || grep -q "Error" $TMPDIR/factorio.log; then
      exit 1
    fi
    ;;
  worlds) run_worlds ;;
  world)
    world_file=$(ls $WORKSPACE/tests/worlds/*/$WORLD.lua 2>/dev/null) || { echo "Unknown world: $WORLD"; exit 1; }
    run_world $world_file
    ;;
esac
