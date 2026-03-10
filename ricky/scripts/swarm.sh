#!/bin/bash
set -euo pipefail

RICK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_ROOT="$(cd "$RICK_DIR/.." && pwd)"

# Source config
CONF="$RICK_DIR/ricky.conf"
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

run_agent() {
  local AGENT=$1
  local PROMPT=$2
  echo "--- Running agent: $AGENT ---" >&2
  claude \
    --system-prompt "$(cat "$RICK_DIR/agents/$AGENT.md")" \
    --print \
    "$PROMPT"
}

# Create feature branch
BRANCH="ai-feature-$(date +%s)"
git checkout -b "$BRANCH" "$BASE_BRANCH"

# Cleanup guidance on failure
cleanup() {
  if [[ $? -ne 0 ]]; then
    echo "Swarm failed on branch '$BRANCH'." >&2
    echo "To return to base branch: git checkout $BASE_BRANCH" >&2
  fi
}
trap cleanup EXIT

# Design phase
if [[ "$SKIP_DESIGN" == false && "$DESIGN_AGENTS" != "none" ]]; then
  SPECS_DIR="$RICK_DIR/prd/specs"
  mkdir -p "$SPECS_DIR"

  echo "=== Design phase ==="
  for AGENT in $DESIGN_AGENTS; do
    if [[ -f "$RICK_DIR/agents/$AGENT.md" ]]; then
      SPEC_FILE="$SPECS_DIR/$(spec_filename "$AGENT")"
      run_agent "$AGENT" "Design for: $TASK" > "$SPEC_FILE"
      echo "Wrote spec: $SPEC_FILE"
    else
      echo "Warning: agent $AGENT not found, skipping" >&2
    fi
  done
fi

# Feature architecture
echo "=== Architecture phase ==="
run_agent architect "$TASK"

# Feature planning
echo "=== Planning phase ==="
run_agent feature-planner "$TASK"

# Implementation (parallel)
echo "=== Implementation phase ==="
run_agent backend "$TASK" &
PID_BACKEND=$!
run_agent frontend "$TASK" &
PID_FRONTEND=$!

IMPL_FAIL=0
wait $PID_BACKEND || IMPL_FAIL=1
wait $PID_FRONTEND || IMPL_FAIL=1
if [[ $IMPL_FAIL -ne 0 ]]; then
  echo "ERROR: Implementation agents failed." >&2
  exit 1
fi

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

# Commit and PR via versioncontroller agent
echo "=== Commit phase ==="
run_agent versioncontroller "Commit and create a PR for: $TASK"

echo "=== Swarm complete ==="
