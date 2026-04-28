# template_base_agent

A template repository for an AI coding agent that automatically implements GitHub issues using [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

## How it works

1. Apply the `doit` label to any GitHub issue.
2. The GitHub Actions workflow (`.github/workflows/doit.yml`) triggers on a self-hosted runner.
3. The runner script (`claude/scripts/issues/doit.sh`):
   - Reads the issue title, body, and comments via `gh`.
   - Clones or updates the target repository.
   - Creates a new branch named `ai/issue-<number>-<random-hex>`.
   - Runs `claude` with the issue details and a prompt template.
   - If Claude needs clarification, it posts questions as an issue comment and stops.
   - Otherwise, commits all changes and pushes the branch.
   - Opens a pull request that references the issue.

## Requirements

- A self-hosted GitHub Actions runner with `gh`, `git`, `claude`, and `openssl` available.
- The runner must be authenticated with `gh` and have write access to the target repository.
- `claude` (Claude Code CLI) must be installed and authenticated on the runner.

## Usage

1. Use this repository as a template.
2. Register a self-hosted runner on the repository.
3. Label any issue with `doit` to trigger automatic implementation.

## Customization

After creating a repository from this template, adapt the following files to your specific project:

- **`CLAUDE.md`** — Project-level instructions loaded by Claude Code on every run. Describe the codebase conventions, architecture, tech stack, and any constraints Claude should follow.
- **`claude/scripts/issues/prompt.md`** — The prompt template injected with each issue's details. Adjust it to set expectations specific to your project (e.g. testing requirements, coding style, how to run the project).
- **`claude/scripts/reviews/prompt.md`** — The prompt template injected with PR review comments. Adjust it to guide how Claude addresses review feedback.
- **`claude/scripts/verify.sh`** — The verification script that runs lints and tests. Adapt it to your project's build system and quality checks.

Keeping these files aligned with the target repository is essential for Claude to produce useful, on-target pull requests.

## File structure

```
CLAUDE.md                   # Project-level context for Claude Code
claude/scripts/
  verify.sh                 # Shared verification script (lint, test, etc.)
  issues/
    doit.sh                 # Issue automation script
    prompt.md               # Prompt template for issues
  reviews/
    submit.sh               # PR review automation script
    prompt.md               # Prompt template for PR reviews
.github/workflows/
  doit.yml                  # Workflow that triggers on the 'doit' label
  review.yml                # Workflow that triggers on PR review submission
```

