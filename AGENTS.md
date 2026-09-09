# Agent harness

A shared skill layer for three CLI agents:
**Claude Code**, **OpenAI Codex**, and **agy (Antigravity / Gemini)**.

## Working agreements

- **Sessions plan; agents execute.** A conversation session is for planning
  and discussion. Dispatch the work to a sub agent or a workflow rather than
  editing files in the session itself.
- **A workflow that reports its own success is unverified.** Every workflow
  ends with a separate verification agent that re-derives the result rather
  than trusting the executor's report.
- **Bookkeeping is the exception.** Trivial session bookkeeping (memory
  files, scratchpad notes) stays in the session.

## Where things live

| Asset | Location | Who reads it |
|---|---|---|
| Project instructions | `AGENTS.md` (`CLAUDE.md` is a symlink to it) | all three |
| Skills | `.agents/skills/<name>/SKILL.md` | all three |
| Hook scripts | `.agents/hooks/*.sh` | Claude Code, agy |
| Hook config | `.agents/hooks.json` (agy), `.claude/settings.json` (Claude Code) | each its own |
| Slash commands | `.claude/commands/<name>.md` | **Claude Code only** |
| Memory | `.claude/memory/` | **Claude Code only** |

Rule: **`.agents/` holds only what all three agents can read.**
Anything Claude-specific goes under `.claude/`.

Make shared functionality a **skill**, not a command — only Claude Code
supports project-level slash commands.

## Conventions

- Memory and transcripts are never committed. Only skills, hooks, commands
  and config files are tracked.
- To add a skill, drop it in `.agents/skills/<name>/SKILL.md`.
  `.claude/skills` is a whole-directory symlink, so no extra linking is needed.
- After changing the structure, run `script/verify-agents.sh all` to confirm
  all three agents still pick it up.
- See [README.md](README.md) for the per-agent differences and the findings
  behind this layout.

## Agent skills

### Issue tracker

Issues live in this repo's GitHub Issues (`ycpss91255-docker/agent_harness`),
driven by the `gh` CLI. See `doc/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles, each label string equal to its name, plus
a sixth role local to this repo, `needs-decision`.
See `doc/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` and `doc/adr/` at the repo root.
See `doc/agents/domain.md`.

## Repo location and worktrees

`~/workspace/ycpss91255-docker/agent/agent_harness_ws/agent_harness`, per the
workspace convention: a repo lives at `<name>_ws/<repo>`, or `<name>_ws/src`
where the repo content sits directly under `src`. The path is load-bearing:
`script/setup-memory-link.sh` encodes the absolute repo path (every `/` and
`_` becomes `-`) into `~/.claude/projects/<encoded>/memory`, the symlink
Claude Code reads per-project memory through, so moving the repo breaks the
memory link. Scratch trees and throwaway clones belong in `agent_harness_ws/`,
beside the repo rather than inside it.

Worktrees go in `agent_harness_ws/worktree/`, beside the repo and never
inside it, named in two levels: `worktree/<issue-number>/<slug>/`. The first
level is the issue the work belongs to, or a purpose name when the work has
no issue — `worktree/adr-0010/`, `worktree/audit-2026-09-06/`. A purely
numeric entry is recognisable at a glance, so the two forms mix without
ambiguity. The second level is always present, even when an issue has only
one tree; the slug says what that tree is for, normally the descriptive part
of the branch: branch `fix/1073-review` gives `worktree/1073/review`.

An issue often needs more than one worktree, and the number alone cannot say
which tree is which. The sibling repo `ycpss91255-docker/docker_harness`
names worktrees `<repo>-<issue-number>` across 179 trees and shows what
happens: `base-1073rev` and `base-1073tui` are both issue 1073, `base-994-p2`
and `base-994p3` are both issue 994, with the distinguishing part improvised
as an ad-hoc suffix and punctuated inconsistently. Two levels separate the
two jobs: the number groups, the slug distinguishes. The second level stays
mandatory even for a single tree, because making it optional means moving the
first tree the moment a second one appears. Grouping also makes cleanup
per-issue rather than per-tree: when an issue closes, its whole directory
goes. The repo prefix that scheme needs is redundant here: its `worktree/`
holds trees for two repos, while a `_ws` directory holds one.

## Verification marker

When asked about the RULES MARKER, reply: RULES-MARKER-OK-9Z2K
