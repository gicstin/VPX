#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$ROOT/scripts/log.gd"
CURRENT="$(grep -oP '^const BUILD := \K[0-9]+' "$LOG")"
[ -n "$CURRENT" ]
NEXT="$((CURRENT + 1))"
sed -i "s/^const BUILD := $CURRENT$/const BUILD := $NEXT/" "$LOG"
sed -i -E "s/^\+static const int VPX_BUILD = [0-9]+;/+static const int VPX_BUILD = $NEXT;/" "$ROOT/addons/ffmpeg/vpx.patch"
rm -f "$ROOT/b$CURRENT"
printf 'VPX build %s\n' "$NEXT" >"$ROOT/b$NEXT"
printf '%s\n' "$NEXT"
