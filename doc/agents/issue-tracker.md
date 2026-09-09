# Issue tracker: GitHub

Issues and specs for this repo live as GitHub issues. Creating and editing one goes through `.agents/scripts/gh-issue.sh`, which checks the conventions below before anything reaches GitHub; every other operation is a plain `gh` CLI call.

## Conventions

- **Create an issue**: `.agents/scripts/gh-issue.sh create --title "scope: ..." --body-file <path> --label <category> [--label <state>]`. Write the body to a file first; the script always hands it to `gh` as `--body-file`, and `--body "..."` is accepted only as a convenience that writes the text out for you. The body carries five sections, in this order: `## Context`, `## Problem`, `## Proposal`, `## Acceptance criteria`, `## Out of scope`. A small issue — a one-line bug, a trivial doc tweak — may collapse `## Proposal` into `## Problem` and drop `## Acceptance criteria`; `## Context` and `## Out of scope` always stay, because they are the two sections that get retroactively wished-for most often. Whichever sections are present keep the order above.
- **Edit an issue**: `.agents/scripts/gh-issue.sh edit <number> --title "..."` / `--body-file <path>`. The target may be the issue number or its URL, the two forms `gh` itself accepts.
- **Read an issue**: `gh issue view <number> --comments`, filtering comments by `jq` and also fetching labels.
- **List issues**: `gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'` with appropriate `--label` and `--state` filters.
- **Comment on an issue**: `gh issue comment <number> --body "..."`
- **Apply / remove labels**: `.agents/scripts/gh-issue.sh edit <number> --add-label "..."` / `--remove-label "..."`. Like `gh`, the label flags take a comma-separated list: `--label "bug,needs-triage"`, with or without a space after the comma. The script splits the list, trims each name, judges every one of them against the rules below, and hands `gh` one `--label` per name.
- **Close**: `gh issue close <number> --comment "..."`

Add `--dry-run` (or set `GH_ISSUE_DRY_RUN=1`) to either script recipe to see the exact `gh` command it would run, checked but not filed. Unknown flags are forwarded to `gh` untouched, so `--repo`, `--assignee` and the rest still work — they keep their order relative to each other, but the script rebuilds the command as title, body file, labels, then everything else. `--` is not an end-of-options marker here: it is forwarded like any other unrecognised word and the arguments after it are still read by the script, which is harmless only because these `gh` subcommands take no positional argument other than the issue number.

Infer the repo from `git remote -v`; `gh` does this automatically when run inside a clone.

## Issue titles

Four rules. They govern issue titles only; this is a repo-local convention.

- **Bare scope prefix, no type.** `scope: description`. The scope is one or two words naming the part of the repo the issue touches: `skill`, `skills`, `hooks`, `prd`, `labels`, `repo`, `docs`. The Conventional-Commits `type(scope)` form is deliberately not used for issue titles: `feat`/`docs`/`fix` restate the `enhancement`/`documentation` category label the issue already carries, while the scope is information no label captures. `type(scope): subject` remains the convention for **commit messages and PR titles** — this rule narrows to issues.
- **State the problem, not the proposed fix.** From Mozilla's Bug Writing Guidelines: a title "should explain the problem, not your suggested solution". Their rejected example is `Browser should work with my web site` — wish-shaped, so it names no problem.
- **Maximum 80 characters.** The empirical basis, recorded so a future reader can judge whether to revisit it: across kubernetes/kubernetes, rust-lang/rust, python/cpython, vuejs/core, angular/angular, microsoft/vscode, denoland/deno and facebook/react, the median issue-title length is 67-90 characters (60 newest open issues per repo, measured 2026-09-08). Mozilla's own 60-character line is met by only 16-41% of titles in those repos. 80 sits inside the observed band.
- **Undecidedness goes in the label, never the title.** An issue whose deliverable is a decision carries `needs-decision` (see [triage-labels.md](triage-labels.md)); the title states the open problem and does not say "decide". Precedent: `rust-lang/rust` tracking-issue titles are identical in shape whether or not the design is settled — `I-needs-decision` and `S-tracking-design-concerns` carry that, not the title.

`.agents/scripts/gh-issue.sh` is where these rules are applied, and it is the entry point for **all three agents**. The file itself is `dist/agents/scripts/gh-issue.sh`; `init.sh` links it to `.agents/scripts/gh-issue.sh` in every repo that installs the harness, which is why that is the path named here and in the hook — it is the only one that is true in a consumer's repo as well as in this one. This repo additionally keeps `script/gh-issue.sh` as a symlink to the same file, so its own older invocation path still works. The shell parses its arguments before it runs, so it reads the real title out of its own argv: there is nothing to tokenise and nothing to guess, and a body quoting an example title cannot be mistaken for a title. It refuses a violation, names the rule and says how to fix it, and never silently corrects a title. The refusal states the rule in its own words and only adds "see this document" where this document is actually present: `dist/` ships the script and does not ship `doc/`, so in a consumer's repo a citation would name a file they were never given. Rules 1 and 3 refuse; rule 4 is a heuristic and only warns; rule 2 is not machine-checkable and is not attempted.

The predecessor was a PreToolUse hook that hand-parsed the whole Bash command string looking for a `--title`. That approach does not converge: two rounds of adversarial review found 22 then 17 defects, and the last of them was a **false deny of the recipe in this document**, because a heredoc body quoting an example title was read as the real title.

What remains as a hook is a nudge. `.agents/hooks/redirect_gh_issue.sh` notices a direct `gh issue create` (or its `new` alias) or `gh issue edit` and points at the script; it never reads or judges a title. A help lookup is exempt — `gh issue create --help`, `gh issue edit 12 --help` — because it prints the flag list and exits without running the command body; the exemption requires the help flag to be the first word after the subcommand, or the first after a single bare target, since `--title --help` files an issue called `--help`. Nothing else is exempt: `--web` opens a prefilled form in a browser, which is a create with a longer path rather than a read. Its matching is anchored at the start of the command string, so the same words inside a heredoc, a quoted example, or a later segment of a `&&` chain are not matched — a missed direct call costs one redirect message, while a false deny blocks real work and catches no mistake. `gh pr` is untouched.

Wiring a second hook alongside this one: Claude Code runs every hook matching an event in parallel, with no short-circuit, and the two-hook arrangement here depends on the details of that. They are stated once, in the header comment of `.agents/hooks/redirect_gh_issue.sh` (`dist/agents/hooks/redirect_gh_issue.sh` in this repo), which is their one home — read them there before adding a hook.

Hooks now reach all three agents, and this document said otherwise until 2026-09-09. The old claim — Codex has no hook mechanism at all — was measured and has expired: codex-cli 0.153.2 reads project hooks from `<repo>/.codex/`, and a hook wired there fires, with a payload whose field names are Claude Code's. The redirect hook is wired for Codex accordingly, in `.codex/hooks.json` rather than under `.agents/`, because `.codex/` is where Codex looks and `.agents/` is measurably not read. `hooks.json` is one of the two files it reads there; `[[hooks.*]]` blocks in `.codex/config.toml` are read as project hooks too, and this repo simply does not use that layer. Its command is `"$(git rev-parse --show-toplevel)/.agents/hooks/redirect_gh_issue.sh"`: Codex runs a hook command through a shell but starts it in the *session's* directory, not the repo root, and sets no project-directory variable, so the command has to find the root itself.

What that does **not** buy is a rule that is always applied, which is still why the rules live in the script. Every hook path is conditional on something this repo does not control. Claude Code's and agy's are wired from policy files a consumer owns and `init.sh` will not edit. Codex's are gated twice — the repo has to be a trusted project in `~/.codex/config.toml` under its exact root path, trust not being inherited from a parent directory, and the hook itself has to have been reviewed — and under `codex exec` both gates fail *in silence*: no hook line, no warning, nothing runs. (Elsewhere the trust gate is loud: the app-server and the TUI print an `ERROR` naming the untrusted `.codex` folder. `codex exec` is the quiet one, and it is the entry point an agent uses.) What is no longer unverified is the deny itself: on 2026-09-09, with both gates cleared, `codex exec` printed `hook: PreToolUse Blocked` and refused the command, with a `gh` stub on `PATH` recording zero invocations. Codex acts on the deny; agy's standing is unchanged and still unverified.

Neither piece is a boundary: `bash -c`, `eval`, a variable holding `gh`, or a title assembled by command substitution all file whatever they please. The rules above are the convention; the script applies them, and the hook only catches the easy misses.

Sibling repos have not adopted this convention; issues filed in them follow whatever they use.

Issue #6 tracks vendoring the `gh-artifact-format` skill, whose section 1 specifies a different title rule (`type(scope): action`, <= 70 characters). When that skill lands, its section 1 is superseded by this document rather than duplicated — one home per topic.

**Known conflict, accepted.** A vendored skill contradicts the hook this repo ships: `dist/agents/skills/setup-matt-pocock-skills/issue-tracker-github.md`, line 7, tells an agent to run `gh issue create --title "..." --body "..."` — the exact command shape `redirect_gh_issue.sh` denies, and an inline body besides. Lines 11, 40 and 44 of the same file name `gh issue edit` and a further `gh issue create`. This is decided, not overlooked: the refusal carries the rule rather than a pointer to it — `dist/agents/scripts/gh-issue.sh`, header: "THE REFUSAL CARRIES THE RULE, NOT A POINTER TO IT" — so an agent that reads the stale skill, tries the denied command and is told the correct invocation in the refusal loses one round trip and nothing else. Editing the vendored file is the worse option: it breaks the content hash in `skills-lock.json`, which is what makes the single install channel restorable, and the edit would be lost at the next upgrade. The file is a *template* the `setup-matt-pocock-skills` skill copies into a repo as its issue-tracker description, so the standing resolution is for that copy to be this document rather than the upstream default.

## Citing sources

How an issue body, a comment, or a document in this repo cites a source. Two forms, picked by whether the source can still move under the citation.

- **A pinned source is cited by file, line and commit hash.** Another repo, or any specific commit: `enforce_gh_body_file.sh:53,62 @ 1a68b19`. The hash is what makes the line numbers reliable, and it is the only citation that survives the source repo being deleted.
- **A living file is cited by section and quoted words, not line numbers.** Anything in this repo that will still be edited: `triage-labels.md`, "Divergence" section: "identical name, colour and description".

Evidence for the split, recorded so a future reader can judge it: during the session that produced this rule a citation of `doc/agents/triage-labels.md:27-28` went stale within that same session, because a later edit shifted the lines; citations pinned at commit `1a68b19` stayed exact.

`ycpss91255-research/vendor_kit` uses the section-plus-quotation form for everything (its `doc/README.md`, "Cross-references" section). This rule extends theirs rather than rejecting it: over a corpus of living documents the two behave identically.

It matters most for citations that leave this repo. A source outside it can be rewritten, renamed, archived or deleted without warning, and once that happens an unpinned citation is unfollowable and unverifiable — so every citation into another repo carries a commit hash.

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
