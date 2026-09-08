# Agent harness

A shared skill layer for three CLI agents:
**Claude Code**, **OpenAI Codex**, and **agy (Antigravity / Gemini)**.

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
- After changing the structure, run `scripts/verify-agents.sh all` to confirm
  all three agents still pick it up.
- See [README.md](README.md) for the per-agent differences and the findings
  behind this layout.

## Verification marker

When asked about the RULES MARKER, reply: RULES-MARKER-OK-9Z2K
