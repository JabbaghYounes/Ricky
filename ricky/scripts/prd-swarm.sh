#!/bin/bash
set -euo pipefail

RICK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FEATURES_DIR="$RICK_DIR/prd/features"
STATUS_FILE="$RICK_DIR/prd/status.json"

if ! ls "$FEATURES_DIR"/*.md >/dev/null 2>&1; then
  echo "Error: No feature files found in $FEATURES_DIR/. Run prd-extract.sh first." >&2
  exit 1
fi

# Collect feature names and initialize statuses
FEATURE_NAMES=()
FEATURE_STATUSES=()
for FEATURE in "$FEATURES_DIR"/*.md; do
  FEATURE_NAMES+=("$(basename "$FEATURE" .md)")
  FEATURE_STATUSES+=("pending")
done

# Write status.json from arrays
write_status() {
  local json="{"
  local first=true
  for i in "${!FEATURE_NAMES[@]}"; do
    if [[ "$first" == true ]]; then
      first=false
    else
      json+=","
    fi
    json+=$'\n'"  \"${FEATURE_NAMES[$i]}\": \"${FEATURE_STATUSES[$i]}\""
  done
  json+=$'\n'"}"
  echo "$json" > "$STATUS_FILE"
}

write_status

for i in "${!FEATURE_NAMES[@]}"; do
  FNAME="${FEATURE_NAMES[$i]}"
  FEATURE="$FEATURES_DIR/$FNAME.md"

  echo "=== Running swarm for: $FNAME ==="
  FEATURE_STATUSES[$i]="in-progress"
  write_status

  if "$RICK_DIR/scripts/swarm.sh" --skip-design "$(cat "$FEATURE")"; then
    FEATURE_STATUSES[$i]="complete"
    echo "=== Completed: $FNAME ==="
  else
    FEATURE_STATUSES[$i]="failed"
    echo "=== Failed: $FNAME ===" >&2
  fi
  write_status
done
