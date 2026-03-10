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
IMPL_AGENTS="${IMPL_AGENTS:-backend frontend}"

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

# Temp file for test output
TEST_OUTPUT_FILE=$(mktemp "${TMPDIR:-/tmp}/ricky-test-output.XXXXXX")

# Cleanup on exit
cleanup() {
  local exit_code=$?
  rm -f "$TEST_OUTPUT_FILE"
  if [[ $exit_code -ne 0 ]]; then
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

# Warn if specs are missing when design was skipped
if [[ "$SKIP_DESIGN" == true ]]; then
  SPECS_DIR="$RICK_DIR/prd/specs"
  if [[ ! -d "$SPECS_DIR" ]] || ! ls "$SPECS_DIR"/*.md >/dev/null 2>&1; then
    echo "WARNING: --skip-design was passed but no spec files found in $SPECS_DIR/." >&2
    echo "Downstream agents will proceed without design specs." >&2
  fi
fi

# Feature architecture (save output for downstream agents)
echo "=== Architecture phase ==="
SPECS_DIR="$RICK_DIR/prd/specs"
mkdir -p "$SPECS_DIR"
FEATURE_ARCH_FILE="$SPECS_DIR/feature-architecture.md"
run_agent architect "$TASK" > "$FEATURE_ARCH_FILE"
echo "Wrote feature architecture: $FEATURE_ARCH_FILE"

# Feature planning (save output for downstream agents)
echo "=== Planning phase ==="
FEATURE_PLAN_FILE="$SPECS_DIR/feature-plan.md"
run_agent feature-planner "$TASK" > "$FEATURE_PLAN_FILE"
echo "Wrote feature plan: $FEATURE_PLAN_FILE"

# Build context for downstream agents
ARCH_CONTEXT=""
PLAN_CONTEXT=""
if [[ -f "$FEATURE_ARCH_FILE" ]]; then
  ARCH_CONTEXT=$(cat "$FEATURE_ARCH_FILE")
fi
if [[ -f "$FEATURE_PLAN_FILE" ]]; then
  PLAN_CONTEXT=$(cat "$FEATURE_PLAN_FILE")
fi

IMPL_PROMPT="Implement this feature: $TASK

## Feature Architecture
$ARCH_CONTEXT

## Implementation Plan
$PLAN_CONTEXT"

# Implementation (parallel if multiple agents)
echo "=== Implementation phase ==="
IMPL_PIDS=()
for AGENT in $IMPL_AGENTS; do
  if [[ -f "$RICK_DIR/agents/$AGENT.md" ]]; then
    run_agent "$AGENT" "$IMPL_PROMPT" &
    IMPL_PIDS+=($!)
  else
    echo "Warning: agent $AGENT not found, skipping" >&2
  fi
done

IMPL_FAIL=0
for PID in "${IMPL_PIDS[@]}"; do
  wait "$PID" || IMPL_FAIL=1
done
if [[ $IMPL_FAIL -ne 0 ]]; then
  echo "ERROR: Implementation agents failed." >&2
  exit 1
fi

# Testing
echo "=== Test phase ==="
TESTER_PROMPT="Write tests for this feature: $TASK

## Feature Architecture
$ARCH_CONTEXT

## Implementation Plan
$PLAN_CONTEXT"
run_agent tester "$TESTER_PROMPT"

# Run tests with retry loop
echo "=== Running tests ==="
RETRY=0
while true; do
  if $TEST_CMD > "$TEST_OUTPUT_FILE" 2>&1; then
    echo "Tests passed."
    break
  fi

  RETRY=$((RETRY + 1))
  if [[ $RETRY -ge $MAX_RETRIES ]]; then
    echo "ERROR: Tests still failing after $MAX_RETRIES retries. Aborting." >&2
    cat "$TEST_OUTPUT_FILE" >&2
    exit 1
  fi

  echo "Tests failed (attempt $RETRY/$MAX_RETRIES). Running debugger..."
  TEST_OUTPUT=$(cat "$TEST_OUTPUT_FILE")
  run_agent debugger "Fix failing tests. Attempt $RETRY of $MAX_RETRIES.

## Test Command
$TEST_CMD

## Test Output
$TEST_OUTPUT"
done

# Commit and PR via versioncontroller agent
echo "=== Commit phase ==="
run_agent versioncontroller "Commit and create a PR for: $TASK

## Git Context
- Current branch: $BRANCH
- Base branch: $BASE_BRANCH
- Push this branch to origin before creating the PR
- Create the PR against $BASE_BRANCH using: gh pr create --base $BASE_BRANCH"

echo "=== Swarm complete ==="
