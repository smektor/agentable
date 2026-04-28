#!/bin/bash
# logging.sh — sets SCRIPT_DIR / VERIFY_SCRIPT and defines log().
# Must be sourced from the top-level calling script so that $0 (and therefore
# SCRIPT_DIR) resolves to the caller's directory, not this file's directory.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERIFY_SCRIPT="${SCRIPT_DIR}/../verify.sh"

log() {
  echo "[$(date +%H:%M:%S)] $*"
}
