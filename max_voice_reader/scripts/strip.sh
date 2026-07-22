#!/usr/bin/env bash
# Replayable strip: delete every path in scripts/strip.manifest from the working tree.
# Idempotent — re-runnable after a fresh `git checkout upstream-mirror` to reproduce
# the lean tree. See scripts/strip.manifest for the PREREQUISITE (de-shell refactor).
#
# Usage: scripts/strip.sh [--dry-run]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="${ROOT}/scripts/strip.manifest"
DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

[ -f "${MANIFEST}" ] || { echo "manifest not found: ${MANIFEST}" >&2; exit 1; }

removed=0
while IFS= read -r line; do
  line="${line%%#*}"
  line="$(echo "$line" | sed 's/[[:space:]]*$//;s/^[[:space:]]*//')"
  [ -z "$line" ] && continue
  target="${ROOT}/${line}"
  if [ ! -e "$target" ]; then
    echo "skip (absent): $line"
    continue
  fi
  if [ "$DRY" = "1" ]; then
    echo "would remove: $line"
    continue
  fi
  if git -C "$ROOT" ls-files --error-unmatch "$line" >/dev/null 2>&1; then
    git -C "$ROOT" rm -r --quiet "$line"
  else
    rm -rf "$target"
  fi
  echo "removed: $line"
  removed=$((removed+1))
done < "${MANIFEST}"

echo "---"
echo "$([ "$DRY" = "1" ] && echo 'dry-run complete' || echo "stripped ${removed} path(s)")"
echo "Next: prune the pubspec deps noted at the bottom of strip.manifest, then 'flutter pub get' and 'flutter analyze'."
