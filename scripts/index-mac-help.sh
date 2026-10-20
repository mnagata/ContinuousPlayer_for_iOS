#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
HELP_DIR="$ROOT_DIR/MacHelp/ContinuousPlayer.help/Contents/Resources/ja.lproj"

# Rebuild after editing the bundled HTML so Help Viewer search stays current.
/usr/bin/hiutil -I corespotlight -C -a -l ja \
  -f "$HELP_DIR/ContinuousPlayer.cshelpindex" "$HELP_DIR"
