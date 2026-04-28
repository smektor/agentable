#!/bin/bash
# Verification script for Claude Code automation.
# This script is intended to be sourced or executed from doit.sh or submit.sh.
# It expects $LOG_FILE and $VERIFY_LOG to be set.
# It sets LINT_EXIT, TYPE_EXIT, and TEST_EXIT.

# Ensure log function exists if not sourced
if ! declare -f log >/dev/null; then
  log() {
    echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG_FILE"
  }
fi

# Check for project-specific verification script
if [ -f "scripts/verify.sh" ]; then
  log "Running project-specific verification script..."
  # Project script should set or return exit codes. 
  # For simplicity, we source it if it expects the same environment.
  source scripts/verify.sh
  return $? 2>/dev/null || exit $?
fi

log "Skipping verification (template placeholder). Implement project-specific checks in scripts/verify.sh or modify this script."

# Default to success in the template
LINT_EXIT=0
TYPE_EXIT=0
TEST_EXIT=0

# Implementation example (commented out for template)
# log "Verifying: lint, type-check, tests..."
# set +e
# make lint 2>&1 | tee -a "$VERIFY_LOG" "$LOG_FILE"
# make lint-check 2>&1 | tee -a "$VERIFY_LOG" "$LOG_FILE"
# LINT_EXIT=${PIPESTATUS[0]}
# make type-check 2>&1 | tee -a "$VERIFY_LOG" "$LOG_FILE"
# TYPE_EXIT=${PIPESTATUS[0]}
# make test 2>&1 | tee -a "$VERIFY_LOG" "$LOG_FILE"
# TEST_EXIT=${PIPESTATUS[0]}
# set -e
