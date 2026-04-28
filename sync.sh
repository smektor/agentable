#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENTABLE_DIR="$SCRIPT_DIR"
MAIN_REPO_DIR="$(dirname "$AGENTABLE_DIR")"

echo "Syncing agentable into: $MAIN_REPO_DIR"

# 1. Copy workflows to .github/workflows/ (overwrite is intentional — keeps CI up to date)
WORKFLOWS_SRC="${AGENTABLE_DIR}/workflows"
WORKFLOWS_DST="${MAIN_REPO_DIR}/.github/workflows"
mkdir -p "$WORKFLOWS_DST"
for f in "$WORKFLOWS_SRC"/*.yml; do
  [ -f "$f" ] || continue
  name="$(basename "$f")"
  cp "$f" "$WORKFLOWS_DST/$name"
  echo "  [workflow] copied $name -> .github/workflows/$name"
done

# 2. Create agentable_scripts/ directory without overwriting any existing scripts
SCRIPTS_DIR="${MAIN_REPO_DIR}/agentable_scripts"
mkdir -p "$SCRIPTS_DIR"

echo ""
echo "agentable_scripts/ hook status (add these to $SCRIPTS_DIR to customise behaviour):"
for hook in preagent.sh postagent.sh doit_preagent.sh doit_postagent.sh review_preagent.sh review_postagent.sh; do
  if [ -f "${SCRIPTS_DIR}/${hook}" ]; then
    echo "  [present] ${hook}"
  else
    echo "  [missing] ${hook}  (optional)"
  fi
done

echo ""
echo "Done."
