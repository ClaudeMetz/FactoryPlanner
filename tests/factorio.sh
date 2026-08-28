#!/bin/bash
set -e

# Factorio locks its write-data directory, so give each worktree one of its own. Pass
# --instance to print it; a --dump-data lands in its script-output
FACTORIO=${FACTORIO:-/opt/factorio/bin/x64/factorio}
GIT="git -C $(dirname $0)"
INSTANCES=$($GIT rev-parse --path-format=absolute --git-common-dir)/factorio-instances
INSTANCE=$INSTANCES/$(basename $($GIT rev-parse --show-toplevel))
CONFIG=$INSTANCE/config/config.ini

[ "$1" = "--instance" ] && { echo $INSTANCE; exit 0; }

# Instances whose worktree is gone, so that removing one is all the teardown there is
WORKTREES=$($GIT worktree list --porcelain | sed -n 's|^worktree .*/||p')
for dir in $INSTANCES/*/; do
  [ -d "$dir" ] || continue
  printf '%s\n' "$WORKTREES" | grep -qxF "$(basename $dir)" || rm -rf "$dir"
done

# Written fresh on every launch, so the instance follows the real config, and so
# no instance keeps an outdated one around
mkdir -p $INSTANCE/config
USERDATA=${FACTORIO_USERDATA:-$HOME/Library/Application Support/factorio}
if [ -f "$USERDATA/config/config.ini" ]; then
  cp "$USERDATA/player-data.json" $INSTANCE/
  sed "s|^write-data=.*|write-data=$INSTANCE|" "$USERDATA/config/config.ini" > $CONFIG
else
  # No read-data entry, so the game deduces it from the executable like it does
  # without a config; the system path it would use instead is for distro installs
  printf '[path]\nwrite-data=%s\n' $INSTANCE > $CONFIG
fi

exec $FACTORIO -c $CONFIG "$@"
