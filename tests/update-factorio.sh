#!/bin/bash
set -e

FACTORIO=${FACTORIO:-/opt/factorio/bin/x64/factorio}
DOWNLOAD=https://factorio.com/get-download/latest/headless/linux64
UPDATE_TMP=$(mktemp -d)
trap 'rm -rf "$UPDATE_TMP"' EXIT

installed_version() {
  "$FACTORIO" --version 2>/dev/null | sed -n '1s/^Version: \([0-9][0-9.]*\).*/\1/p'
}

# Best effort: an update failure is reported without blocking the following test run
install_root=${FACTORIO%/bin/x64/factorio}
[ "$install_root" = "$FACTORIO" ] && exit 0

url=$(curl -sIL -o /dev/null -w '%{url_effective}' --max-time 30 "$DOWNLOAD") || url=""
latest=$(printf '%s' "$url" | sed -n 's/.*_\([0-9][0-9.]*\)\.tar\.xz.*/\1/p')
current=$(installed_version)

if [ -z "$latest" ] || [ -z "$current" ]; then
  echo "WARNING: update check failed, using installed Factorio"
  exit 0
elif [ "$latest" = "$current" ]; then
  echo "Factorio $current is up to date"
  exit 0
fi

echo "Updating Factorio $current -> $latest"
if ! curl -sfL --max-time 600 "$url" -o "$UPDATE_TMP/headless.tar.xz"; then
  echo "WARNING: download of Factorio $latest failed, using $current"
elif ! tar -xJf "$UPDATE_TMP/headless.tar.xz" -C "$(dirname "$install_root")"; then
  echo "WARNING: extraction failed, check write access to $install_root; using $current"
else
  echo "Factorio updated to $(installed_version)"
fi
exit 0
