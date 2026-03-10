#!/bin/bash
set -euo pipefail

RICK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FEATURES_DIR="$RICK_DIR/prd/features"

if ! ls "$FEATURES_DIR"/*.md >/dev/null 2>&1; then
  echo "Error: No feature files found in $FEATURES_DIR/. Run prd-extract.sh first." >&2
  exit 1
fi

for FEATURE in "$FEATURES_DIR"/*.md; do
  FNAME=$(basename "$FEATURE" .md)
  echo "=== Running swarm for: $FNAME ==="
  "$RICK_DIR/scripts/swarm.sh" --skip-design "$(cat "$FEATURE")"
  echo "=== Completed: $FNAME ==="
done
