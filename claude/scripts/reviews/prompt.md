Repository: $REPO
Pull request title: $PR_TITLE
Pull request description: $PR_BODY

Review comments:
$COMMENTS

Read all the review comments above and apply the requested changes to the codebase where possible.

After applying the changes, output ONLY the following section (no other text before or after it):

---PR_SUMMARY---
A short summary of what was changed (2-5 bullet points). Do NOT include any preamble - output only the bullet points.

If any review comment is unclear, asks a question, or requires a decision you cannot make without more information, stop immediately - do NOT make any file changes. Instead, your entire response must be exactly:
QUESTIONS:
<your questions here>
Do not write anything before QUESTIONS: and do not attempt any partial implementation.
