#!/bin/bash
# logging.sh — sets up log paths and defines the log() helper.
# Must be sourced from the top-level calling script so that $0 (and therefore
# SCRIPT_DIR) resolves to the caller's directory, not this file's directory.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/../logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/$(date +%Y-%m-%d).log"
VERIFY_SCRIPT="${SCRIPT_DIR}/../verify.sh"

log() {
  echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG_FILE"
}
