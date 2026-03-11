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
DESIGN_MODEL="${DESIGN_MODEL:-claude-sonnet-4-6}"
MAX_TURNS="${MAX_TURNS:-25}"
RATE_LIMIT_WAIT="${RATE_LIMIT_WAIT:-600}"

# Source shared functions (rate-limit retry, logging, etc.)
source "$RICK_DIR/scripts/lib.sh"

command -v claude >/dev/null || { echo "Error: claude CLI not found" >&2; exit 1; }

# Clean previous features
rm -rf "$FEATURES_DIR"
mkdir -p "$FEATURES_DIR"

cd "$PROJECT_ROOT"

echo "Extracting features from PRD..."

TURNS_FLAG=""
if [[ "$MAX_TURNS" -gt 0 ]]; then
  TURNS_FLAG="--max-turns $MAX_TURNS"
fi

# Set up logging for product-manager agent
export RICKY_FEATURE_SLUG="extract"
local_log=$(_agent_log_path "product-manager")
if [[ -n "$local_log" ]]; then
  export RICKY_AGENT_LOG="$local_log"
fi

RAW=$(run_claude \
  --system-prompt "$(cat "$RICK_DIR/agents/product-manager.md")" \
  --print \
  $CLAUDE_PERMISSIONS \
  --model "$DESIGN_MODEL" \
  $TURNS_FLAG \
  "Read the following PRD and extract features.

$(cat "$PRD")")

unset RICKY_AGENT_LOG

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
