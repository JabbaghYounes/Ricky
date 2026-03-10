#!/bin/bash
set -euo pipefail

RICK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_ROOT="$(cd "$RICK_DIR/.." && pwd)"

# Source config
CONF="$RICK_DIR/rick.conf"
[[ -f "$CONF" ]] && source "$CONF"

# Defaults
TEST_CMD="${TEST_CMD:-npm test}"
BASE_BRANCH="${BASE_BRANCH:-main}"
MAX_RETRIES="${MAX_RETRIES:-3}"
DESIGN_AGENTS="${DESIGN_AGENTS:-system-architect db-designer api-designer ux-designer}"

# Parse flags
SKIP_DESIGN=false
if [[ "${1:-}" == "--skip-design" ]]; then
  SKIP_DESIGN=true
  shift
fi

TASK="${1:-}"

# Validate
if [[ -z "$TASK" ]]; then
  echo "Usage: swarm.sh [--skip-design] <task description>" >&2
  exit 1
fi

command -v claude >/dev/null || { echo "Error: claude CLI not found" >&2; exit 1; }

cd "$PROJECT_ROOT"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "Error: not a git repo" >&2; exit 1; }

run_agent() {
  local AGENT=$1
  local PROMPT=$2
  echo "--- Running agent: $AGENT ---"
  claude \
    --system-prompt "$(cat "$RICK_DIR/agents/$AGENT.md")" \
    --print \
    "$PROMPT"
}

# Create feature branch
BRANCH="ai-feature-$(date +%s)"
git checkout -b "$BRANCH" "$BASE_BRANCH"

# Design phase
if [[ "$SKIP_DESIGN" == false && "$DESIGN_AGENTS" != "none" ]]; then
  SPECS_DIR="$RICK_DIR/prd/specs"
  mkdir -p "$SPECS_DIR"

  echo "=== Design phase ==="
  for AGENT in $DESIGN_AGENTS; do
    if [[ -f "$RICK_DIR/agents/$AGENT.md" ]]; then
      run_agent "$AGENT" "Design for: $TASK"
    else
      echo "Warning: agent $AGENT not found, skipping" >&2
    fi
  done
fi

# Feature architecture
echo "=== Architecture phase ==="
run_agent architect "$TASK"

# Implementation (parallel)
echo "=== Implementation phase ==="
run_agent backend "$TASK" &
run_agent frontend "$TASK" &
wait

# Testing
echo "=== Test phase ==="
run_agent tester "$TASK"

# Run tests with retry loop
echo "=== Running tests ==="
RETRY=0
while true; do
  if $TEST_CMD; then
    echo "Tests passed."
    break
  fi

  RETRY=$((RETRY + 1))
  if [[ $RETRY -ge $MAX_RETRIES ]]; then
    echo "ERROR: Tests still failing after $MAX_RETRIES retries. Aborting." >&2
    exit 1
  fi

  echo "Tests failed (attempt $RETRY/$MAX_RETRIES). Running debugger..."
  run_agent debugger "Fix failing tests. Attempt $RETRY of $MAX_RETRIES."
done

# Commit and PR
echo "=== Commit phase ==="
git add .
git commit -m "feat: $TASK"

gh pr create \
  --title "Feature: $TASK" \
  --body "Generated from PRD by rick"

echo "=== Swarm complete ==="
