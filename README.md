# agentable

Agentable is a set of GitHub Actions workflows and shell scripts that let a self-hosted runner automatically implement GitHub issues and address PR review comments using Claude Code.

Add it to your repository as a Git submodule under the `agentable/` directory. When a maintainer labels an issue **`doit`** or submits a PR review, the corresponding workflow fires, Claude makes the necessary code changes, runs verification, and opens (or updates) a pull request — all without manual intervention.

---

## Prerequisites

The self-hosted runner machine must have:

- [`gh`](https://cli.github.com/) — GitHub CLI, authenticated (`gh auth login`)
- [`claude`](https://docs.anthropic.com/en/docs/claude-code) — Claude Code CLI, authenticated
- `git`, `bash`, `openssl` (standard on Linux/macOS)

---

## Setup

### 1. Add as a submodule

```bash
git submodule add <this-repo-url> agentable
git submodule update --init
```

### 2. Run sync.sh

From the root of your repository:

```bash
bash agentable/sync.sh
```

This will:
- Copy `agentable/workflows/*.yml` into `.github/workflows/` (overwrites existing files — safe to re-run after updates).
- Create an `agentable_scripts/` directory in your repo root (does **not** overwrite any scripts you have already placed there).

### 3. Commit

```bash
git add .github/workflows/ agentable_scripts/ agentable
git commit -m "chore: add agentable"
git push
```

---

## Workflow triggers

| Workflow | File | Trigger |
|---|---|---|
| **Do It** | `.github/workflows/doit.yml` | Issue labeled `doit` |
| **Review Submit** | `.github/workflows/review.yml` | PR review submitted |

### Do It (`doit` label)

1. Reads the issue title, body, and comments.
2. Clones / updates the target repository on the runner.
3. Creates a new branch `ai/issue-<number>-<random>`.
4. Runs the **preagent** hook (see below).
5. Invokes Claude Code with the issue content as the prompt (up to 15 turns).
6. If Claude asks questions instead of implementing, posts them as an issue comment and stops.
7. Runs the **postagent** hook (verification). On failure, retries Claude once.
8. Commits and pushes, then opens a pull request linked to the issue.

#### Issue parameters

The issue body is scanned for optional control parameters in bold key-value format:

| Parameter | Values | Default | Notes |
|---|---|---|---|
| `**Model:**` | `haiku` \| `sonnet` \| `opus` | `sonnet` | `opus` is capped at `sonnet` unless the runner has `ALLOW_OPUS=true` set |
| `**Max turns:**` | any positive integer | `15` | Maximum number of Claude agentic turns for the main run; the verification retry is always capped at 10 |

#### Example issue body

```
Implement a rate-limiting middleware for the API endpoints.

All routes under `/api/` should be limited to 100 requests per minute per IP.
Return HTTP 429 when the limit is exceeded. Use Redis for the counter.

**Model:** sonnet
**Max turns:** 20
```

Parameters are optional — an issue with plain prose and no parameters works fine.

### Review Submit

1. Reads the PR title, body, and all review / inline comments.
2. Checks out the PR branch.
3. Runs the **preagent** hook.
4. Invokes Claude Code with the review comments as the prompt (up to 10 turns).
5. Runs the **postagent** hook. On failure, retries Claude once.
6. Commits, pushes, and posts a summary comment on the PR.

---

## Hook scripts

Place optional hook scripts in `agentable_scripts/` at the root of your repository. All scripts are called with `bash` and must exit `0` on success.

| Script | Runs when | Scope |
|---|---|---|
| `preagent.sh` | Before Claude (both workflows) | General fallback |
| `postagent.sh` | After Claude, before commit (both) | General fallback |
| `doit_preagent.sh` | Before Claude (issue workflow only) | Specific — overrides `preagent.sh` |
| `doit_postagent.sh` | After Claude, before commit (issue workflow) | Specific — overrides `postagent.sh` |
| `review_preagent.sh` | Before Claude (review workflow only) | Specific — overrides `preagent.sh` |
| `review_postagent.sh` | After Claude, before commit (review workflow) | Specific — overrides `postagent.sh` |

**Precedence:** specific scripts take priority over general ones. If neither exists, that hook phase is silently skipped.

### preagent scripts

Run **before** Claude. Use them for environment setup — installing dependencies, seeding caches, exporting environment variables, etc.

A non-zero exit code aborts the run immediately.

```bash
# agentable_scripts/preagent.sh
#!/bin/bash
set -e
npm ci          # ensure node_modules are up to date before Claude touches the code
```

### postagent scripts

Run **after** Claude makes its changes, **before** the commit. They replace the legacy `verify.sh` mechanism. Use them to run linting, type-checking, and tests.

A non-zero exit code triggers a one-shot Claude retry. If verification still fails after the retry, an error comment is posted on the issue / PR and the run aborts without committing anything.

stdout and stderr are captured and included in the retry prompt so Claude can see exactly what failed.

```bash
# agentable_scripts/postagent.sh
#!/bin/bash
set -e
npm run lint
npm run type-check
npm test
```

---

## Legacy: verify.sh

If no postagent hook script is found **and** a file called `verify.sh` exists at `agentable/scripts/verify.sh` (relative to the runner's working directory), it is sourced for backward compatibility. It is expected to set `LINT_EXIT`, `TYPE_EXIT`, and `TEST_EXIT` variables. New setups should use `postagent.sh` instead.

---

## Internal scripts

Three helper scripts in `scripts/` are sourced by both `doit.sh` and `submit.sh` at startup. You do not need to modify them; customise behaviour through the `agentable_scripts/` hooks instead.

| File | Purpose |
|---|---|
| `scripts/logging.sh` | Sets `SCRIPT_DIR`, `VERIFY_SCRIPT`; defines `log()` |
| `scripts/hooks.sh` | Defines `resolve_hook()` for locating `agentable_scripts/` hook files |
| `scripts/run_verify.sh` | Defines `_run_verify()` — runs postagent hook, or falls back to legacy `verify.sh` |
| `scripts/prepare_repo.sh` | Defines `prepare_repo()` — clones or fetches the target repo, sets `REPO_DIR` |

---

## Directory layout (after setup)

```
your-repo/
├── .github/
│   └── workflows/
│       ├── doit.yml          ← copied by sync.sh
│       └── review.yml        ← copied by sync.sh
├── agentable/                ← this submodule
│   ├── scripts/
│   │   ├── logging.sh        ← log setup + log()
│   │   ├── hooks.sh          ← resolve_hook()
│   │   ├── run_verify.sh     ← _run_verify()
│   │   ├── prepare_repo.sh   ← prepare_repo()
│   │   ├── issues/
│   │   │   ├── doit.sh
│   │   │   └── prompt.md
│   │   └── reviews/
│   │       ├── submit.sh
│   │       └── prompt.md
│   ├── workflows/
│   ├── sync.sh
│   └── README.md
└── agentable_scripts/        ← your customisation hooks (optional)
    ├── preagent.sh
    ├── postagent.sh
    ├── doit_preagent.sh
    ├── doit_postagent.sh
    ├── review_preagent.sh
    └── review_postagent.sh
```
