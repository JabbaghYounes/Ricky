#!/bin/bash
set -euo pipefail

RICK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_ROOT="$(cd "$RICK_DIR/.." && pwd)"

# Source config
CONF="$RICK_DIR/ricky.conf"
[[ -f "$CONF" ]] && source "$CONF"

DESIGN_AGENTS="${DESIGN_AGENTS:-system-architect db-designer api-designer ux-designer}"

# Validate
if [[ ! -f "$RICK_DIR/prd/prd.md" ]] || [[ ! -s "$RICK_DIR/prd/prd.md" ]]; then
  echo "Error: No PRD found at ricky/prd/prd.md" >&2
  exit 1
fi

command -v claude >/dev/null || { echo "Error: claude CLI not found" >&2; exit 1; }

echo "=========================================="
echo " RICK: Full product pipeline"
echo "=========================================="

# Step 1: Extract features from PRD
echo ""
echo "--- Step 1: Extracting features from PRD ---"
"$RICK_DIR/scripts/prd-extract.sh"

# Step 2: Product-level design (runs once, not per-feature)
if [[ "$DESIGN_AGENTS" != "none" ]]; then
  echo ""
  echo "--- Step 2: Product-level design ---"
  cd "$PROJECT_ROOT"
  SPECS_DIR="$RICK_DIR/prd/specs"
  mkdir -p "$SPECS_DIR"

  for AGENT in $DESIGN_AGENTS; do
    if [[ -f "$RICK_DIR/agents/$AGENT.md" ]]; then
      echo "Running design agent: $AGENT"
      claude \
        --system-prompt "$(cat "$RICK_DIR/agents/$AGENT.md")" \
        --print \
        "Design based on the PRD at $RICK_DIR/prd/prd.md"
    else
      echo "Warning: agent $AGENT not found, skipping" >&2
    fi
  done
fi

# Step 3: Run per-feature swarms (design already done above)
echo ""
echo "--- Step 3: Running feature swarms ---"
"$RICK_DIR/scripts/prd-swarm.sh"

echo ""
echo "=========================================="
echo " RICK: Pipeline complete"
echo "=========================================="
