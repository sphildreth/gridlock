---
name: gh-cli
description: GitHub CLI (gh) quick workflows and pointers. Use when working with GitHub from the terminal (issues, pull requests, Actions, releases) or when the user mentions `gh`, "GitHub CLI", "pull request", "PR", "issue", "workflow", or "Actions".
license: Apache-2.0
---

# GitHub CLI (gh)

This skill provides a lightweight entrypoint for using GitHub CLI effectively.
For the full command reference, see:
- [Complete gh reference](./references/gh-cli-reference.md)

## When to use this skill

- You need to create/review/update PRs from the terminal
- You need to file or triage issues
- You need to inspect or rerun GitHub Actions workflows
- You need to manage releases

## Prerequisites

- `gh` installed (`gh --version`)
- Authenticated (`gh auth status`)

## Common workflows

### Auth + Git credential helper

- Login: `gh auth login`
- Set up git credential helper: `gh auth setup-git`

### Pull requests

- Create PR: `gh pr create`
- View PR: `gh pr view --web` (or omit `--web` for terminal)
- Check PR status: `gh pr status`
- Checkout PR locally: `gh pr checkout <number>`

### Issues

- Create issue: `gh issue create`
- List issues: `gh issue list`

### Actions

- List runs: `gh run list`
- View a run: `gh run view <run-id>`
- Download artifacts: `gh run download <run-id>`

## Troubleshooting

- Auth problems: run `gh auth status`, then `gh auth login` (or `gh auth refresh`)
- Wrong host (enterprise vs github.com): use `--hostname` in auth commands
