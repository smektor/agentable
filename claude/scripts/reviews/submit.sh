#!/bin/bash
set -e

PR_NUMBER=$1
REPO=$2

# Logging setup
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/../logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/$(date +%Y-%m-%d).log"
VERIFY_SCRIPT="${SCRIPT_DIR}/../verify.sh"

log() {
  echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG_FILE"
}

log "=== Run started: PR #${PR_NUMBER} repo=${REPO} ==="

log "[1/6] Reading PR #${PR_NUMBER} from ${REPO}..."
PR_TITLE=$(gh pr view $PR_NUMBER -R $REPO --json title -q .title)
PR_BODY=$(gh pr view $PR_NUMBER -R $REPO --json body -q .body)
PR_BRANCH=$(gh pr view $PR_NUMBER -R $REPO --json headRefName -q .headRefName)
REVIEW_COMMENTS=$(gh pr view $PR_NUMBER -R $REPO --json reviews -q '.reviews[] | "### Review by " + .author.login + " (" + .state + ")\n" + .body' 2>/dev/null || echo "")
INLINE_COMMENTS=$(gh api "repos/${REPO}/pulls/${PR_NUMBER}/comments" --jq '.[] | "### Comment by " + .user.login + " on `" + .path + "` line " + (.line | tostring) + ":\n" + .body' 2>/dev/null || echo "")
COMMENTS="${REVIEW_COMMENTS}"
if [ -n "$INLINE_COMMENTS" ]; then
  COMMENTS="${COMMENTS}\n\n### Inline comments:\n${INLINE_COMMENTS}"
fi
log "PR Title: $PR_TITLE"
log "PR Branch: $PR_BRANCH"
log "PR Body: $(echo "$PR_BODY" | head -c 500)$([ ${#PR_BODY} -gt 500 ] && echo '...[truncated]')"
[ -n "$COMMENTS" ] && log "Comments: $(echo "$COMMENTS" | head -c 500)$([ ${#COMMENTS} -gt 500 ] && echo '...[truncated]')"

# Clone or update repo
REPO_NAME=$(basename $REPO)
REPO_DIR=~/repos/$REPO_NAME

log "[2/6] Preparing repository at ${REPO_DIR}..."
if [ -d "$REPO_DIR" ]; then
  log "Repo exists, updating..."
  cd $REPO_DIR
  git fetch
else
  log "Cloning repo..."
  mkdir -p ~/repos
  gh repo clone $REPO $REPO_DIR
  cd $REPO_DIR
fi

log "Checking out PR branch: ${PR_BRANCH}..."
git checkout $PR_BRANCH
git pull origin $PR_BRANCH

log "[3/6] Running Claude Code..."
PROMPT=$(REPO="$REPO" PR_TITLE="$PR_TITLE" PR_BODY="$PR_BODY" COMMENTS="$COMMENTS" envsubst < "$(dirname "$0")/prompt.md")
log "Model: claude-sonnet-4-6"
set +e
CLAUDE_OUTPUT=$(claude --dangerously-skip-permissions --model "claude-sonnet-4-6" --max-turns 10 --print "$PROMPT" 2>&1)
CLAUDE_EXIT=$?
set -e
log "--- Claude output (exit=${CLAUDE_EXIT}) ---"
echo "$CLAUDE_OUTPUT" | tee -a "$LOG_FILE"
log "--- End Claude output ---"
if [ $CLAUDE_EXIT -ne 0 ]; then
  log "Claude failed with exit code ${CLAUDE_EXIT}. Aborting."
  exit 1
fi

if echo "$CLAUDE_OUTPUT" | grep -q "^QUESTIONS:"; then
  log "Claude has questions. Posting as PR comment and stopping."
  gh pr comment $PR_NUMBER -R $REPO --body "$CLAUDE_OUTPUT"
  exit 0
fi

log "[4/6] Verifying..."
VERIFY_LOG=$(mktemp)
source "$VERIFY_SCRIPT"
log "Verification results — lint=${LINT_EXIT} type=${TYPE_EXIT} test=${TEST_EXIT}"

if [ $((LINT_EXIT + TYPE_EXIT + TEST_EXIT)) -ne 0 ]; then
  log "Verification failed. Re-invoking Claude to fix errors (1 retry)..."
  VERIFY_ERRORS=$(cat "$VERIFY_LOG")
  RETRY_PROMPT="You previously addressed review comments on PR #${PR_NUMBER} (${PR_TITLE}). The following verification errors were found. Fix only what is failing — do not make unrelated changes.

Errors:
${VERIFY_ERRORS}

After fixing, output ONLY:
---PR_SUMMARY---
<bullet points of what was changed>"

  if [ $TEST_EXIT -eq 0 ]; then
    RETRY_MODEL="claude-haiku-4-5-20251001"
    log "Only lint/type-check failed — using haiku for retry"
  else
    RETRY_MODEL="claude-sonnet-4-6"
    log "Tests failed — using sonnet for retry"
  fi

  set +e
  CLAUDE_OUTPUT=$(claude --dangerously-skip-permissions --model "$RETRY_MODEL" --max-turns 10 --print "$RETRY_PROMPT" 2>&1)
  CLAUDE_EXIT=$?
  set -e
  log "--- Claude retry output (exit=${CLAUDE_EXIT}) ---"
  echo "$CLAUDE_OUTPUT" | tee -a "$LOG_FILE"
  log "--- End Claude retry output ---"
  if [ $CLAUDE_EXIT -ne 0 ]; then
    log "Claude retry failed with exit code ${CLAUDE_EXIT}. Aborting."
    exit 1
  fi

  truncate -s 0 "$VERIFY_LOG"
  source "$VERIFY_SCRIPT"
  log "Retry verification results — lint=${LINT_EXIT} type=${TYPE_EXIT} test=${TEST_EXIT}"

  if [ $((LINT_EXIT + TYPE_EXIT + TEST_EXIT)) -ne 0 ]; then
    log "Verification still failing after retry. Posting to PR and aborting."
    ERROR_BODY=$(printf "### Automated fix failed\n\nVerification errors after retry:\n\`\`\`\n%s\n\`\`\`\n\nManual intervention required." "$(cat "$VERIFY_LOG")")
    gh pr comment $PR_NUMBER -R $REPO --body "$ERROR_BODY"
    rm -f "$VERIFY_LOG"
    exit 1
  fi
fi
rm -f "$VERIFY_LOG"

log "[5/6] Committing and pushing..."
git add -A -- ':!.env'
if git diff --cached --quiet; then
  log "No changes made by Claude. Exiting."
  exit 0
fi
git diff --cached --stat | tee -a "$LOG_FILE"
git commit -m "feat: address review comments on PR #${PR_NUMBER}"
git push origin $PR_BRANCH

log "[6/6] Posting summary comment on PR..."
PR_SUMMARY=$(echo "$CLAUDE_OUTPUT" | awk '/^---PR_SUMMARY---/{found=1; next} found{print}')

if [ -n "$PR_SUMMARY" ]; then
  gh pr comment $PR_NUMBER -R $REPO --body "$(printf "### Changes made in response to review\n\n%s" "$PR_SUMMARY")"
  log "Posted summary comment."
fi

log "Done! Changes pushed and comments posted on PR #${PR_NUMBER}."
log "=== Run finished ==="
