# <project>

<!--
Project instructions for Claude Code, Codex and agy.

CLAUDE.md is a symlink to this file, so all three read the same text; write it
once here. This file is yours -- init.sh copies it in when it is missing and
never touches it again, so an upgrade will not overwrite what you put here.

What the harness already provides, and what you should not restate:
  .agents/skills/    vendored skills, symlinked in
  .agents/hooks/     hook scripts
  .claude/           the entry points Claude Code needs

Add your own skills next to the vendored ones in .agents/skills/<name>/ and
your own commands in .claude/commands/. Both directories mix the two.
-->

## Working agreements

- **Sessions plan; agents execute.** A conversation session is for planning
  and discussion. Dispatch the work to a sub agent or a workflow rather than
  editing files in the session itself.
- **A workflow that reports its own success is unverified.** Every workflow
  ends with a separate verification agent that re-derives the result rather
  than trusting the executor's report.
- **Bookkeeping is the exception.** Trivial session bookkeeping (memory
  files, scratchpad notes) stays in the session.
