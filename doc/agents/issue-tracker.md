# Issue tracker: GitHub

Issues and specs for this repo live as GitHub issues. Creating and editing one goes through `.agents/scripts/gh-issue.sh`, which checks the conventions below before anything reaches GitHub; every other operation is a plain `gh` CLI call.

## Conventions

- **Create an issue**: `.agents/scripts/gh-issue.sh create --title "scope: ..." --body-file <path> --label <category> [--label <state>]`. Write the body to a file first; the script always hands it to `gh` as `--body-file`, and `--body "..."` is accepted only as a convenience that writes the text out for you. The body carries five sections, in this order: `## Context`, `## Problem`, `## Proposal`, `## Acceptance criteria`, `## Out of scope`.
- **Edit an issue**: `.agents/scripts/gh-issue.sh edit <number> --title "..."` / `--body-file <path>`. The target may be the issue number or its URL, the two forms `gh` itself accepts.
- **Read an issue**: `gh issue view <number> --comments`, filtering comments by `jq` and also fetching labels.
- **List issues**: `gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'` with appropriate `--label` and `--state` filters.
- **Comment on an issue**: `gh issue comment <number> --body "..."`
- **Apply / remove labels**: `.agents/scripts/gh-issue.sh edit <number> --add-label "..."` / `--remove-label "..."`. Like `gh`, the label flags take a comma-separated list: `--label "bug,needs-triage"`, with or without a space after the comma. The script splits the list, trims each name, judges every one of them against the rules below, and hands `gh` one `--label` per name.
- **Close**: `gh issue close <number> --comment "..."`

Add `--dry-run` (or set `GH_ISSUE_DRY_RUN=1`) to either script recipe to see the exact `gh` command it would run, checked but not filed. Unknown flags are forwarded to `gh` untouched, so `--repo`, `--assignee` and the rest still work — they keep their order relative to each other, but the script rebuilds the command as title, body file, labels, then everything else. `--` is not an end-of-options marker here: it is forwarded like any other unrecognised word and the arguments after it are still read by the script, which is harmless only because these `gh` subcommands take no positional argument other than the issue number.

Infer the repo from `git remote -v`; `gh` does this automatically when run inside a clone.

## Pull requests as a triage surface

**PRs as a request surface: no.** _(Set to `yes` if this repo treats external PRs as feature requests; `/triage` reads this flag.)_

When set to `yes`, PRs run through the same labels and states as issues, using the `gh pr` equivalents:

- **Read a PR**: `gh pr view <number> --comments` and `gh pr diff <number>` for the diff.
- **List external PRs for triage**: `gh pr list --state open --json number,title,body,labels,author,authorAssociation,comments` then keep only `authorAssociation` of `CONTRIBUTOR`, `FIRST_TIME_CONTRIBUTOR`, or `NONE` (drop `OWNER`/`MEMBER`/`COLLABORATOR`).
- **Comment / label / close**: `gh pr comment`, `gh pr edit --add-label`/`--remove-label`, `gh pr close`.

GitHub shares one number space across issues and PRs, so a bare `#42` may be either: resolve with `gh pr view 42` and fall back to `gh issue view 42`.

## When a skill says "publish to the issue tracker"

Create a GitHub issue.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <number> --comments`.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a single issue with **child** issues as tickets.

- **Map**: a single issue labelled `wayfinder:map`, holding the Notes / Decisions-so-far / Fog body. `.agents/scripts/gh-issue.sh create --label wayfinder:map ...`, which still needs its category label.
- **Child ticket**: an issue linked to the map as a GitHub sub-issue (`gh api` on the sub-issues endpoint). Where sub-issues aren't enabled, add the child to a task list in the map body and put `Part of #<map>` at the top of the child body. Labels: `wayfinder:<type>` (`research`/`prototype`/`grilling`/`task`). Once claimed, the ticket is assigned to the driving dev.
- **Blocking**: GitHub's **native issue dependencies**, the canonical, UI-visible representation. Add an edge with `gh api --method POST repos/<owner>/<repo>/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`, where `<blocker-db-id>` is the blocker's numeric **database id** (`gh api repos/<owner>/<repo>/issues/<n> --jq .id`, _not_ the `#number` or `node_id`). GitHub reports `issue_dependencies_summary.blocked_by` (open blockers only, the live gate). Where dependencies aren't available, fall back to a `Blocked by: #<n>, #<n>` line at the top of the child body. A ticket is unblocked when every blocker is closed.
- **Frontier query**: list the map's open children (`gh issue list --state open`, scoped to the map's sub-issues / task list), drop any with an open blocker (`issue_dependencies_summary.blocked_by > 0`, or an open issue in the `Blocked by` line) or an assignee; first in map order wins.
- **Claim**: `.agents/scripts/gh-issue.sh edit <n> --add-assignee @me`, the session's first write.
- **Resolve**: `gh issue comment <n> --body "<answer>"`, then `gh issue close <n>`, then append a context pointer (gist + link) to the map's Decisions-so-far.
