#!/bin/bash
# hooks.sh — defines resolve_hook() for locating agentable_scripts/ hooks.

# Resolve the most-specific available hook script.
# Usage: resolve_hook <specific_path> <general_path>
# Prints the path of the found script, or nothing if neither exists.
resolve_hook() {
  if [ -f "$1" ]; then
    echo "$1"
  elif [ -f "$2" ]; then
    echo "$2"
  fi
}
