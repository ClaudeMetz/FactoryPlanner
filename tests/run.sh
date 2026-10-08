#!/bin/bash
set -e

FACTORIO=${FACTORIO:-/opt/factorio/bin/x64/factorio}
WORKSPACE=${GITHUB_WORKSPACE:-$(cd "$(dirname "$0")/.." && pwd)}
# Every game launch goes through the wrapper, which gives this worktree a write-data
# directory of its own so runs from several worktrees don't lock each other out
RUN=$WORKSPACE/tests/factorio.sh

usage() {
  echo "Usage: bash tests/run.sh <save-create | suites | suite <name> [configuration] [case-filter]>"
  echo "The case filter is a Lua pattern matched against test names"
}

TEST=${1:-save-create}
SUITE=${2:-}
CONFIGURATION=${3:-}
CASES=${4:-}
case $TEST in
  save-create | suites) [ $# -le 1 ] || { usage; exit 2; } ;;
  suite)
    [ $# -ge 2 ] && [ $# -le 4 ] || { usage; exit 2; }
    [[ $SUITE =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] && [ -f "$WORKSPACE/tests/suites/$SUITE/suite.lua" ] \
      || { echo "Unknown suite: $SUITE"; exit 2; }
    ;;
  -h | --help) usage; exit 0 ;;
  *) usage; exit 2 ;;
esac

# Tests run on a save rather than a fresh map, since they need an actual player,
# which only a save can carry. Adding factoryplanner runs on_init and the test runner
SAVE=$WORKSPACE/tests/test.zip
DOWNLOAD=https://factorio.com/get-download/latest/headless/linux64

TEST_TMP=$(mktemp -d)
trap 'rm -rf "$TEST_TMP"' EXIT
FAILURE_DIR=""

RED=$'\033[31m'; GREEN=$'\033[32m'; BOLD=$'\033[1m'; RESET=$'\033[0m'

installed_version() {
  "$FACTORIO" --version 2>/dev/null | sed -n '1s/^Version: \([0-9][0-9.]*\).*/\1/p'
}

# Never fatal: a failed update leaves the existing install in place and tests run on it
update_factorio() {
  local root=${FACTORIO%/bin/x64/factorio}
  [ "$root" = "$FACTORIO" ] && return 0

  local url latest current
  url=$(curl -sIL -o /dev/null -w '%{url_effective}' --max-time 30 "$DOWNLOAD") || url=""
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
  if ! curl -sfL --max-time 600 "$url" -o "$TEST_TMP/headless.tar.xz"; then
    echo "WARNING: download of Factorio $latest failed, using $current"
  elif ! tar -xJf "$TEST_TMP/headless.tar.xz" -C "$(dirname "$root")"; then
    echo "WARNING: extraction failed, check write access to $root; using $current"
  else
    echo "Factorio updated to $(installed_version)"
  fi
  return 0
}

# Preserve only failed logs; all mod copies and successful logs are removed on exit
preserve_log() {
  local logfile=$1 name=$2
  if [ -z "$FAILURE_DIR" ]; then
    FAILURE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/factoryplanner-test-failures.XXXXXX")
  fi
  cp "$logfile" "$FAILURE_DIR/$name.log"
  echo "    Log: $FAILURE_DIR/$name.log"
}

# Quote CLI values as Lua strings, including patterns containing quotes or backslashes
lua_string() {
  local value=$1
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  printf '"%s"' "$value"
}

count_label() {
  local count=$1 noun=$2
  [ "$count" -eq 1 ] || noun=${noun}s
  printf '%s %s' "$count" "$noun"
}

# Run one configuration with a fresh mod copy and save load
# RUN_* values let the suite aggregate results and discover its remaining configurations
run_configuration() {
  local suite_dir=$1 configuration=$2 cases=$3
  local suite=$(basename "$suite_dir")
  local mods=$TEST_TMP/mods logfile=$TEST_TMP/run.log report=$TEST_TMP/report
  RUN_PASSED=0
  RUN_CONFIGURATIONS=""

  rm -rf "$mods"
  mkdir -p "$mods"
  cp -r "$WORKSPACE/modfiles" "$mods/factoryplanner" || return 1
  cp -r "$WORKSPACE/tests/mod" "$mods/factoryplanner-test" || return 1
  cp -r "$suite_dir" "$mods/factoryplanner-test/suite" || return 1
  {
    printf 'return {configuration='
    if [ -n "$configuration" ]; then lua_string "$configuration"; else printf 'nil'; fi
    printf ', filter='
    lua_string "$cases"
    printf '}\n'
  } > "$mods/factoryplanner-test/options.lua"

  # Pin the full mod set so runs don't depend on the installation's defaults
  cat > "$mods/mod-list.json" << EOF
{
    "mods": [
        { "name": "base", "enabled": true },
        { "name": "recycler", "enabled": true },
        { "name": "space-age", "enabled": false },
        { "name": "quality", "enabled": false },
        { "name": "elevated-rails", "enabled": false },
        { "name": "factoryplanner", "enabled": true },
        { "name": "factoryplanner-test", "enabled": true }
    ]
}
EOF

  # Expansion suites may supply their own pinned mod set.
  if [ -f "$suite_dir/mod-list.json" ]; then
    cp "$suite_dir/mod-list.json" "$mods/mod-list.json"
  fi

  local exit_code=0
  "$RUN" --mod-directory "$mods" --benchmark "$SAVE" --benchmark-ticks 1 > "$logfile" 2>&1 || exit_code=$?

  RUN_CONFIGURATIONS=$(sed -n 's/^.*FPTEST_CONFIGURATION \([a-zA-Z0-9_-]*\)$/\1/p' "$logfile")
  local selected=$(sed -n 's/^.*FPTEST_SELECTED \([a-zA-Z0-9_-]*\)$/\1/p' "$logfile")
  local label=${selected:-${configuration:-first configuration}}
  local result=$(sed -n 's/^.*FPTEST_RESULT \([0-9]* [0-9]*\)$/\1/p' "$logfile")
  local failed=0 reason=""
  if [ -n "$result" ]; then
    RUN_PASSED=${result% *}
    failed=${result#* }
  fi
  sed -n '/FPTEST_REPORT$/,/FPTEST_REPORT_END$/{/FPTEST_REPORT/!p;}' "$logfile" > "$report"

  if grep -q "FPTEST_SETUP_FAILED" "$logfile"; then
    reason="test setup failed"
  elif [ "$exit_code" -ne 0 ]; then
    reason="game failed"
  elif [ -z "$result" ]; then
    reason="tests did not run"
  elif [ "$failed" -gt 0 ]; then
    reason="$failed failed, $RUN_PASSED passed"
  elif [ "$RUN_PASSED" -eq 0 ]; then
    reason="no test cases selected"
  fi

  sed "s/✓/${GREEN}✓${RESET}/; s/✗/${RED}✗${RESET}/" "$report"
  [ -n "$reason" ] || return 0

  if [ ! -s "$report" ] || [ "$reason" = "game failed" ]; then
    echo "  ${RED}✗${RESET} $reason [$label]"
    # Startup and prototype errors may happen before the Lua runner can report
    tail -n 20 "$logfile" | sed 's/^/    | /'
  fi
  preserve_log "$logfile" "$suite-${selected:-startup}"
  return 1
}

run_suite() {
  local suite_dir=$1 configuration=${2:-} cases=${3:-}
  local passed=0 failed=0 count=1
  echo "${BOLD}$(basename "$suite_dir")${RESET}"

  # The first configuration also provides the ordered list for the rest of the suite
  run_configuration "$suite_dir" "$configuration" "$cases" || failed=$((failed + 1))
  passed=$RUN_PASSED
  local configurations=$RUN_CONFIGURATIONS
  if [ -z "$configuration" ]; then
    local next first=true
    for next in $configurations; do
      if [ "$first" = true ]; then first=false; continue; fi
      run_configuration "$suite_dir" "$next" "$cases" || failed=$((failed + 1))
      passed=$((passed + RUN_PASSED))
      count=$((count + 1))
    done
  fi

  local summary="$passed passed · $(count_label "$count" configuration)"
  if [ "$failed" -gt 0 ]; then summary="$summary · $(count_label "$failed" configuration) failed"; fi
  echo "  $summary"
  [ "$failed" -eq 0 ]
}

# Run every suite, reporting all failures rather than stopping at the first
run_suites() {
  local suite_dir failed="" count=0
  for suite_dir in "$WORKSPACE"/tests/suites/*; do
    [ -f "$suite_dir/suite.lua" ] || continue
    run_suite "$suite_dir" || failed="$failed $(basename "$suite_dir")"
    count=$((count + 1))
  done
  [ "$count" -gt 0 ] || { echo "No suites found"; return 1; }
  if [ -n "$failed" ]; then
    echo "${RED}Failed suites:$failed${RESET}"
    return 1
  fi
  echo "${GREEN}All suites passed${RESET}"
}

update_factorio

case $TEST in
  save-create)
    mkdir -p "$TEST_TMP/mods"
    cp -r "$WORKSPACE/modfiles" "$TEST_TMP/mods/factoryplanner"
    exit_code=0
    "$RUN" --mod-directory "$TEST_TMP/mods" --create "$TEST_TMP/test-map.zip" > "$TEST_TMP/factorio.log" 2>&1 || exit_code=$?
    if [ "$exit_code" -ne 0 ] || grep -q "Error" "$TEST_TMP/factorio.log"; then
      tail -n 20 "$TEST_TMP/factorio.log" | sed 's/^/  | /'
      echo "${RED}✗ save-create: mod error during map creation${RESET}"
      preserve_log "$TEST_TMP/factorio.log" save-create
      exit 1
    fi
    echo "${GREEN}✓${RESET} save-create: map created without errors"
    ;;
  suites) run_suites ;;
  suite) run_suite "$WORKSPACE/tests/suites/$SUITE" "$CONFIGURATION" "$CASES" ;;
esac
