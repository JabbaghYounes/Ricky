#!/bin/bash
# Shared functions for ricky scripts
# Source this from other scripts: source "$RICK_DIR/scripts/lib.sh"

# Default rate limit wait (seconds) — can be overridden in ricky.conf
RATE_LIMIT_WAIT="${RATE_LIMIT_WAIT:-600}"

# Check if file content indicates a rate limit
is_rate_limited() {
  local file=$1
  grep -qiE "hit your limit|rate.?limit|too many requests|overloaded|usage limit" "$file" 2>/dev/null
}

# Run claude with automatic rate-limit detection and retry.
# Captures stdout to a temp file, checks for rate limit patterns,
# sleeps and retries if rate-limited. On success, outputs to stdout
# so callers can redirect as usual (e.g., > spec-file.md).
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

    cat "$tmpfile"
    rm -f "$tmpfile"
    return 0
  done
}
