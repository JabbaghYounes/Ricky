#!/bin/bash
set -euo pipefail

RICK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_ROOT="$(cd "$RICK_DIR/.." && pwd)"

# Source config
CONF="$RICK_DIR/ricky.conf"
[[ -f "$CONF" ]] && source "$CONF"

PRD="$RICK_DIR/prd/prd.md"
FEATURES_DIR="$RICK_DIR/prd/features"

# Validate
if [[ ! -f "$PRD" ]] || [[ ! -s "$PRD" ]]; then
  echo "Error: PRD not found or empty at $PRD" >&2
  exit 1
fi

CLAUDE_PERMISSIONS="${CLAUDE_PERMISSIONS:---dangerously-skip-permissions}"

command -v claude >/dev/null || { echo "Error: claude CLI not found" >&2; exit 1; }

# Clean previous features
rm -rf "$FEATURES_DIR"
mkdir -p "$FEATURES_DIR"

cd "$PROJECT_ROOT"

echo "Extracting features from PRD..."

RAW=$(claude \
  --system-prompt "$(cat "$RICK_DIR/agents/product-manager.md")" \
  --print \
  $CLAUDE_PERMISSIONS \
  "Read the following PRD and extract features.

$(cat "$PRD")")

# Split on ---FEATURE--- delimiter and write individual files
echo "$RAW" | awk -v dir="$FEATURES_DIR" '
  /^---FEATURE---$/ {
    if (outfile) close(outfile)
    getline slug
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", slug)
    outfile = dir "/" slug ".md"
    next
  }
  outfile { print >> outfile }
'

COUNT=$(find "$FEATURES_DIR" -name "*.md" 2>/dev/null | wc -l)
echo "Extracted $COUNT feature(s) to $FEATURES_DIR/"
