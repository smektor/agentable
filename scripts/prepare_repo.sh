#!/bin/bash
# prepare_repo.sh — defines prepare_repo() to clone or update a repository.
# Sets REPO_DIR to the local path of the repository and cds into it.
#
# Usage: prepare_repo <owner/repo> [--update-main]
#   --update-main  also switch to main and pull before returning
#                  (use for issue workflows that create a new branch)

prepare_repo() {
  local repo=$1
  local update_main=${2:-}

  REPO_DIR=~/repos/$(basename "$repo")

  if [ -d "$REPO_DIR" ]; then
    log "Repo exists, fetching latest..."
    cd "$REPO_DIR"
    git fetch
    if [ "$update_main" = "--update-main" ]; then
      git checkout main
      git pull
    fi
  else
    log "Cloning ${repo}..."
    mkdir -p ~/repos
    gh repo clone "$repo" "$REPO_DIR"
    cd "$REPO_DIR"
  fi
}
