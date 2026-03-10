#!/bin/bash
set -euo pipefail

RICK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FEATURES_DIR="$RICK_DIR/prd/features"
STATUS_FILE="$RICK_DIR/prd/status.json"

if ! ls "$FEATURES_DIR"/*.md >/dev/null 2>&1; then
  echo "Error: No feature files found in $FEATURES_DIR/. Run prd-extract.sh first." >&2
  exit 1
fi

# Read existing status if available (enables resume after failure)
read_existing_status() {
  local name=$1
  if [[ -f "$STATUS_FILE" ]]; then
    # Extract status for this feature using grep/sed (no jq dependency)
    local status
    status=$(grep "\"$name\"" "$STATUS_FILE" 2>/dev/null | sed 's/.*: *"\([^"]*\)".*/\1/' || true)
    echo "${status:-pending}"
  else
    echo "pending"
  fi
}

# Collect feature names and load statuses (resume-aware)
FEATURE_NAMES=()
FEATURE_STATUSES=()
for FEATURE in "$FEATURES_DIR"/*.md; do
  FNAME="$(basename "$FEATURE" .md)"
  FEATURE_NAMES+=("$FNAME")
  FEATURE_STATUSES+=("$(read_existing_status "$FNAME")")
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

HAS_FAILURE=false

for i in "${!FEATURE_NAMES[@]}"; do
  FNAME="${FEATURE_NAMES[$i]}"
  FEATURE="$FEATURES_DIR/$FNAME.md"

  # Skip features already completed in a previous run
  if [[ "${FEATURE_STATUSES[$i]}" == "complete" ]]; then
    echo "=== Skipping (already complete): $FNAME ==="
    continue
  fi

  echo "=== Running swarm for: $FNAME ==="
  FEATURE_STATUSES[$i]="in-progress"
  write_status

  if "$RICK_DIR/scripts/swarm.sh" --skip-design "$(cat "$FEATURE")"; then
    FEATURE_STATUSES[$i]="complete"
    echo "=== Completed: $FNAME ==="
  else
    FEATURE_STATUSES[$i]="failed"
    HAS_FAILURE=true
    echo "=== Failed: $FNAME ===" >&2
  fi
  write_status
done

if [[ "$HAS_FAILURE" == true ]]; then
  echo "ERROR: One or more features failed. See $STATUS_FILE for details." >&2
  exit 1
fi
