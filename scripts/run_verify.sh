#!/bin/bash
# run_verify.sh — defines _run_verify() for running postagent / legacy verify.sh.
# Requires the following variables to be set by the caller:
#   $POSTAGENT    — path to postagent hook script (may be empty)
#   $VERIFY_LOG   — path to a temp file for capturing output
#   $VERIFY_SCRIPT — path to the legacy verify.sh (set by logging.sh)
#   $LOG_FILE     — path to the run log (set by logging.sh)
# Sets:
#   $VERIFY_EXIT  — 0 on pass, non-zero on failure

_run_verify() {
  truncate -s 0 "$VERIFY_LOG"
  if [ -n "$POSTAGENT" ]; then
    log "Running postagent hook: $(basename $POSTAGENT)..."
    set +e
    bash "$POSTAGENT" > "$VERIFY_LOG" 2>&1
    VERIFY_EXIT=$?
    set -e
    cat "$VERIFY_LOG" | tee -a "$LOG_FILE"
  elif [ -f "$VERIFY_SCRIPT" ]; then
    source "$VERIFY_SCRIPT"
    VERIFY_EXIT=$((LINT_EXIT + TYPE_EXIT + TEST_EXIT))
  else
    VERIFY_EXIT=0
  fi
}
