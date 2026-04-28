#!/bin/bash
set -e

ISSUE_NUMBER=$1
REPO=$2
BRANCH="ai/issue-${ISSUE_NUMBER}-$(openssl rand -hex 4)"

# shellcheck source=../logging.sh
source "$(cd "$(dirname "$0")" && pwd)/../logging.sh"
# shellcheck source=../hooks.sh
source "$(cd "$(dirname "$0")" && pwd)/../hooks.sh"
# shellcheck source=../run_verify.sh
source "$(cd "$(dirname "$0")" && pwd)/../run_verify.sh"
# shellcheck source=../prepare_repo.sh
source "$(cd "$(dirname "$0")" && pwd)/../prepare_repo.sh"

log "=== Run started: issue #${ISSUE_NUMBER} repo=${REPO} branch=${BRANCH} ==="

log "[1/7] Reading issue #${ISSUE_NUMBER} from ${REPO}..."
TITLE=$(gh issue view $ISSUE_NUMBER -R $REPO --json title -q .title)
BODY=$(gh issue view $ISSUE_NUMBER -R $REPO --json body -q .body)
COMMENTS=$(gh issue view $ISSUE_NUMBER -R $REPO --json comments -q '.comments[] | "### Comment by " + .author.login + "\n" + .body' 2>/dev/null || echo "")
log "Title: $TITLE"
log "Body: $(echo "$BODY" | head -c 500)$([ ${#BODY} -gt 500 ] && echo '...[truncated]')"
[ -n "$COMMENTS" ] && log "Comments: $(echo "$COMMENTS" | head -c 500)$([ ${#COMMENTS} -gt 500 ] && echo '...[truncated]')"

log "[2/7] Preparing repository for ${REPO}..."
prepare_repo "$REPO" --update-main

log "[3/7] Creating branch ${BRANCH}..."
git checkout -b $BRANCH

# --- Preagent hook (runs before Claude; aborts on non-zero exit) ---
PREAGENT=$(resolve_hook "${REPO_DIR}/agentable_scripts/doit_preagent.sh" "${REPO_DIR}/agentable_scripts/preagent.sh")
if [ -n "$PREAGENT" ]; then
  log "Running preagent hook: $(basename $PREAGENT)..."
  bash "$PREAGENT" || { log "Preagent hook failed. Aborting."; exit 1; }
fi

log "[4/7] Running Claude Code..."
PROMPT=$(REPO="$REPO" TITLE="$TITLE" BODY="$BODY" COMMENTS="$COMMENTS" envsubst < "$(dirname "$0")/prompt.md")

# Model routing: read from issue body, cap opus at sonnet unless ALLOW_OPUS=true
ALLOW_OPUS=${ALLOW_OPUS:-false}
MODEL_RAW=$(echo "$BODY" | grep -oP '(?<=\*\*Model:\*\* )\w+' | head -1)
case "${MODEL_RAW:-sonnet}" in
  haiku) CLAUDE_MODEL="claude-haiku-4-5-20251001" ;;
  opus)
    if [ "$ALLOW_OPUS" = "true" ]; then
      CLAUDE_MODEL="claude-opus-4-7"
    else
      log "Opus requested but ALLOW_OPUS=false — using sonnet"
      CLAUDE_MODEL="claude-sonnet-4-6"
    fi
    ;;
  *) CLAUDE_MODEL="claude-sonnet-4-6" ;;
esac
log "Model: ${CLAUDE_MODEL} (requested: ${MODEL_RAW:-sonnet})"

# Max turns routing: read from issue body, default 15
MAX_TURNS_RAW=$(echo "$BODY" | grep -oP '(?<=\*\*Max turns:\*\* )\d+' | head -1)
CLAUDE_MAX_TURNS=${MAX_TURNS_RAW:-15}
log "Max turns: ${CLAUDE_MAX_TURNS} (requested: ${MAX_TURNS_RAW:-default})"

set +e
CLAUDE_OUTPUT=$(claude --dangerously-skip-permissions --model "$CLAUDE_MODEL" --max-turns "$CLAUDE_MAX_TURNS" --print "$PROMPT" 2>&1)
CLAUDE_EXIT=$?
set -e
log "--- Claude output (exit=${CLAUDE_EXIT}) ---"
log "$CLAUDE_OUTPUT"
log "--- End Claude output ---"
if [ $CLAUDE_EXIT -ne 0 ]; then
  log "Claude failed with exit code ${CLAUDE_EXIT}. Aborting."
  exit 1
fi

if echo "$CLAUDE_OUTPUT" | grep -q "^QUESTIONS:"; then
  log "Claude has questions. Posting as issue comment and stopping."
  gh issue comment $ISSUE_NUMBER -R $REPO --body "$CLAUDE_OUTPUT"
  exit 0
fi

log "[5/7] Verifying..."
POSTAGENT=$(resolve_hook "${REPO_DIR}/agentable_scripts/doit_postagent.sh" "${REPO_DIR}/agentable_scripts/postagent.sh")
VERIFY_LOG=$(mktemp)

_run_verify
log "Verification results — exit=${VERIFY_EXIT}"

if [ "$VERIFY_EXIT" -ne 0 ]; then
  log "Verification failed. Re-invoking Claude to fix errors (1 retry)..."
  VERIFY_ERRORS=$(cat "$VERIFY_LOG")
  RETRY_PROMPT="You previously implemented issue #${ISSUE_NUMBER} (${TITLE}). The following verification errors were found. Fix only what is failing — do not make unrelated changes.

Errors:
${VERIFY_ERRORS}

After fixing, output ONLY:
---PR_SUMMARY---
<bullet points of what was changed>"

  RETRY_MODEL="$CLAUDE_MODEL"
  log "Using ${RETRY_MODEL} for retry"

  set +e
  CLAUDE_OUTPUT=$(claude --dangerously-skip-permissions --model "$RETRY_MODEL" --max-turns 10 --print "$RETRY_PROMPT" 2>&1)
  CLAUDE_EXIT=$?
  set -e
  log "--- Claude retry output (exit=${CLAUDE_EXIT}) ---"
  log "$CLAUDE_OUTPUT"
  log "--- End Claude retry output ---"
  if [ $CLAUDE_EXIT -ne 0 ]; then
    log "Claude retry failed with exit code ${CLAUDE_EXIT}. Aborting."
    exit 1
  fi

  _run_verify
  log "Retry verification results — exit=${VERIFY_EXIT}"

  if [ "$VERIFY_EXIT" -ne 0 ]; then
    log "Verification still failing after retry. Posting to issue and aborting."
    ERROR_BODY=$(printf "### Automated implementation failed\n\nVerification errors after retry:\n\`\`\`\n%s\n\`\`\`\n\nManual intervention required." "$(cat "$VERIFY_LOG")")
    gh issue comment $ISSUE_NUMBER -R $REPO --body "$ERROR_BODY"
    rm -f "$VERIFY_LOG"
    exit 1
  fi
fi
rm -f "$VERIFY_LOG"

log "[6/7] Committing and pushing..."
git add -A -- ':!.env'
if git diff --cached --quiet; then
  log "No changes made by Claude. Exiting."
  exit 0
fi
git diff --cached --stat
git commit -m "feat: implement issue #${ISSUE_NUMBER} - ${TITLE}"
git push origin $BRANCH

log "[7/7] Creating PR and posting comments..."
PR_URL=$(gh pr create -R $REPO \
  --title "$TITLE" \
  --body "Closes #${ISSUE_NUMBER}" \
  --head $BRANCH \
  --base main)

PR_NUMBER=$(echo "$PR_URL" | grep -oE '[0-9]+$')

PR_SUMMARY=$(echo "$CLAUDE_OUTPUT" | awk '/^---PR_SUMMARY---/{found=1; next} found{print}')

if [ -n "$PR_SUMMARY" ]; then
  gh pr comment $PR_NUMBER -R $REPO --body "$(printf "### Summary\n\n%s" "$PR_SUMMARY")"
  log "Posted PR summary comment."
fi

log "PR URL: ${PR_URL}"
log "Done! PR created for issue #${ISSUE_NUMBER}."
log "=== Run finished ==="
