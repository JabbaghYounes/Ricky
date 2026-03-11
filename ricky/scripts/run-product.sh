#!/bin/bash
set -euo pipefail

RICK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_ROOT="$(cd "$RICK_DIR/.." && pwd)"

# Source config
CONF="$RICK_DIR/ricky.conf"
[[ -f "$CONF" ]] && source "$CONF"

DESIGN_AGENTS="${DESIGN_AGENTS:-system-architect db-designer api-designer ux-designer}"
CLAUDE_PERMISSIONS="${CLAUDE_PERMISSIONS:---dangerously-skip-permissions}"
DESIGN_MODEL="${DESIGN_MODEL:-claude-sonnet-4-6}"
MAX_TURNS="${MAX_TURNS:-25}"
RATE_LIMIT_WAIT="${RATE_LIMIT_WAIT:-600}"

# Source shared functions (rate-limit retry, etc.)
source "$RICK_DIR/scripts/lib.sh"

# Map design agent names to spec filenames
spec_filename() {
  case "$1" in
    system-architect) echo "architecture.md" ;;
    db-designer)      echo "db-schema.md" ;;
    api-designer)     echo "api-spec.md" ;;
    ux-designer)      echo "ux-spec.md" ;;
    *)                echo "$1.md" ;;
  esac
}

# Validate
if [[ ! -f "$RICK_DIR/prd/prd.md" ]] || [[ ! -s "$RICK_DIR/prd/prd.md" ]]; then
  echo "Error: No PRD found at ricky/prd/prd.md" >&2
  exit 1
fi

command -v claude >/dev/null || { echo "Error: claude CLI not found" >&2; exit 1; }

echo "=========================================="
echo " RICKY: Full product pipeline"
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
      SPEC_FILE="$SPECS_DIR/$(spec_filename "$AGENT")"
      echo "Running design agent: $AGENT"
      TURNS_FLAG=""
      if [[ "$MAX_TURNS" -gt 0 ]]; then
        TURNS_FLAG="--max-turns $MAX_TURNS"
      fi
      run_claude \
        --system-prompt "$(cat "$RICK_DIR/agents/$AGENT.md")" \
        --print \
        $CLAUDE_PERMISSIONS \
        --model "$DESIGN_MODEL" \
        $TURNS_FLAG \
        "Design based on the PRD at $RICK_DIR/prd/prd.md" > "$SPEC_FILE"
      echo "Wrote spec: $SPEC_FILE"
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
echo " RICKY: Pipeline complete"
echo "=========================================="
