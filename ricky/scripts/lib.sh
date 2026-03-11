#!/bin/bash
# Shared functions for ricky scripts
# Source this from other scripts: source "$RICK_DIR/scripts/lib.sh"

# Default rate limit wait (seconds) — can be overridden in ricky.conf
RATE_LIMIT_WAIT="${RATE_LIMIT_WAIT:-600}"

# --- Logging ---

# Initialize a log directory for this pipeline run.
# Sets RICKY_RUN_LOG_DIR (exported so child processes inherit it).
# Call once at the start of run-product.sh or swarm.sh.
init_run_log() {
  local log_base="${LOG_DIR:-${RICK_DIR:-/tmp}/prd/logs}"
  export RICKY_RUN_LOG_DIR="$log_base/run-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$RICKY_RUN_LOG_DIR"
  echo "Logs: $RICKY_RUN_LOG_DIR" >&2
}

# Compute a log file path for an agent call.
# Usage: log_path <agent-name>
# Respects RICKY_FEATURE_SLUG (set by prd-swarm.sh or swarm.sh).
_agent_log_path() {
  local agent=$1
  if [[ -z "${RICKY_RUN_LOG_DIR:-}" ]]; then
    echo ""
    return
  fi
  local subdir="${RICKY_FEATURE_SLUG:-standalone}"
  local dir="$RICKY_RUN_LOG_DIR/$subdir"
  mkdir -p "$dir"
  echo "$dir/${agent}-$(date +%s).log"
}

# --- Rate limiting ---

# Check if file content indicates a rate limit
is_rate_limited() {
  local file=$1
  grep -qiE "hit your limit|rate.?limit|too many requests|overloaded|usage limit" "$file" 2>/dev/null
}

# Run claude with automatic rate-limit detection and retry.
# Captures stdout to a temp file, checks for rate limit patterns,
# sleeps and retries if rate-limited. On success, outputs to stdout
# so callers can redirect as usual (e.g., > spec-file.md).
# If RICKY_AGENT_LOG is set, also writes output to that file.
# If RICKY_COST_LOG is set, appends token usage to CSV.
run_claude() {
  local tmpfile
  tmpfile=$(mktemp "${TMPDIR:-/tmp}/ricky-claude.XXXXXX")

  while true; do
    # Run claude, capture stdout. Allow non-zero exit (rate limit may not be an error code).
    claude "$@" > "$tmpfile" 2>&1 || true

    if is_rate_limited "$tmpfile"; then
      echo "RATE LIMIT: Pausing for ${RATE_LIMIT_WAIT}s ($(date '+%H:%M:%S'))..." >&2
      echo "Will resume at $(date -d "+${RATE_LIMIT_WAIT} seconds" '+%H:%M:%S' 2>/dev/null || echo "~$(( RATE_LIMIT_WAIT / 60 ))m from now")." >&2
      sleep "$RATE_LIMIT_WAIT"
      continue
    fi

    # Write to log file if set
    if [[ -n "${RICKY_AGENT_LOG:-}" ]]; then
      cp "$tmpfile" "$RICKY_AGENT_LOG"
    fi

    # Extract and log token usage if cost tracking is enabled
    if [[ -n "${RICKY_COST_LOG:-}" ]]; then
      _log_token_usage "$tmpfile"
    fi

    cat "$tmpfile"
    rm -f "$tmpfile"
    return 0
  done
}

# --- Cost/Token Tracking ---

# Initialize cost tracking for a pipeline run.
# Sets RICKY_COST_LOG (exported so child processes inherit it).
init_cost_tracking() {
  if [[ -n "${RICKY_RUN_LOG_DIR:-}" ]]; then
    export RICKY_COST_LOG="$RICKY_RUN_LOG_DIR/cost.csv"
  fi
}

# Extract token usage from claude output and append to cost CSV.
# Looks for token usage patterns in the output. The claude CLI may include
# usage stats when run with certain flags. This function attempts to parse them.
_log_token_usage() {
  local file=$1
  [[ -n "${RICKY_COST_LOG:-}" ]] || return 0

  local agent="${RICKY_AGENT_NAME:-unknown}"
  local feature="${RICKY_FEATURE_SLUG:-unknown}"
  local model="${RICKY_AGENT_MODEL:-unknown}"
  local ts
  ts=$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')

  # Try to extract token counts from output
  # Claude CLI may output usage info in various formats
  local input_tokens="0"
  local output_tokens="0"

  # Pattern 1: JSON format (--output-format json)
  if grep -q '"input_tokens"' "$file" 2>/dev/null; then
    input_tokens=$(grep -o '"input_tokens":[0-9]*' "$file" | head -1 | grep -o '[0-9]*' || echo "0")
    output_tokens=$(grep -o '"output_tokens":[0-9]*' "$file" | head -1 | grep -o '[0-9]*' || echo "0")
  fi

  # Pattern 2: Text format (verbose output)
  if [[ "$input_tokens" == "0" ]] && grep -qiE "input tokens|tokens used" "$file" 2>/dev/null; then
    input_tokens=$(grep -oiE "input.?tokens:?\s*[0-9,]+" "$file" | head -1 | grep -o '[0-9]*' | head -1 || echo "0")
    output_tokens=$(grep -oiE "output.?tokens:?\s*[0-9,]+" "$file" | head -1 | grep -o '[0-9]*' | head -1 || echo "0")
  fi

  # Append to cost log (create with header if new)
  if [[ ! -f "$RICKY_COST_LOG" ]]; then
    echo "agent,feature,input_tokens,output_tokens,model,timestamp" > "$RICKY_COST_LOG"
  fi
  echo "$agent,$feature,$input_tokens,$output_tokens,$model,$ts" >> "$RICKY_COST_LOG"
}

# --- Granular status tracking ---

# Status directory: one file per feature with key=value pairs
# Format: ricky/prd/status/<feature-slug>.status
# Keys: status, branch, stage_design, stage_architect, stage_implement, stage_test, stage_debug, stage_review, stage_commit, last_updated

RICKY_STATUS_DIR="${RICKY_STATUS_DIR:-${RICK_DIR:-/tmp}/prd/status}"

# Read a key from a feature's status file
# Usage: read_feature_status <slug> <key>
read_feature_status() {
  local slug=$1 key=$2
  local file="$RICKY_STATUS_DIR/$slug.status"
  if [[ -f "$file" ]]; then
    grep "^${key}=" "$file" 2>/dev/null | head -1 | cut -d= -f2- || true
  fi
}

# Write a key=value to a feature's status file (atomic via flock)
# Usage: write_feature_status <slug> <key> <value>
write_feature_status() {
  local slug=$1 key=$2 value=$3
  local file="$RICKY_STATUS_DIR/$slug.status"
  mkdir -p "$RICKY_STATUS_DIR"
  (
    flock -x 200
    if [[ -f "$file" ]] && grep -q "^${key}=" "$file" 2>/dev/null; then
      # Update existing key
      sed -i "s|^${key}=.*|${key}=${value}|" "$file"
    else
      # Append new key
      echo "${key}=${value}" >> "$file"
    fi
    # Always update timestamp
    if [[ "$key" != "last_updated" ]]; then
      local ts
      ts=$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')
      if grep -q "^last_updated=" "$file" 2>/dev/null; then
        sed -i "s|^last_updated=.*|last_updated=${ts}|" "$file"
      else
        echo "last_updated=${ts}" >> "$file"
      fi
    fi
  ) 200>"$file.lock"
}

# Write a stage status for a feature
# Usage: write_stage_status <slug> <stage> <status>
write_stage_status() {
  local slug=$1 stage=$2 status=$3
  write_feature_status "$slug" "stage_${stage}" "$status"
  write_feature_status "$slug" "status" "$( _compute_overall_status "$slug" )"
}

# Compute overall feature status from stage statuses
_compute_overall_status() {
  local slug=$1
  local file="$RICKY_STATUS_DIR/$slug.status"
  [[ -f "$file" ]] || { echo "pending"; return; }
  if grep -q "=failed$" "$file" 2>/dev/null; then
    echo "failed"
  elif grep -q "=in-progress$" "$file" 2>/dev/null; then
    echo "in-progress"
  elif grep -qE "stage_commit=complete" "$file" 2>/dev/null; then
    echo "complete"
  else
    echo "in-progress"
  fi
}

# Generate status.json from per-feature status files (for backward compatibility)
generate_status_json() {
  local status_file="${1:-${RICK_DIR:-/tmp}/prd/status.json}"
  local json="{"
  local first=true
  if [[ -d "$RICKY_STATUS_DIR" ]]; then
    for f in "$RICKY_STATUS_DIR"/*.status; do
      [[ -f "$f" ]] || continue
      local slug
      slug=$(basename "$f" .status)
      local status
      status=$(read_feature_status "$slug" "status")
      status="${status:-pending}"
      if [[ "$first" == true ]]; then
        first=false
      else
        json+=","
      fi
      json+=$'\n'"  \"${slug}\": \"${status}\""
    done
  fi
  json+=$'\n'"}"
  echo "$json" > "$status_file"
}
