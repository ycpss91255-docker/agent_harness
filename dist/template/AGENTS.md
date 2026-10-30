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

## Commits

Commit with `.agents/scripts/assisted-commit.sh`, not `git commit`. It is
`git commit` with an `Assisted-by:` trailer added when an agent is the one
committing, and every argument it does not claim itself is forwarded to git
untouched. Call it as a plain command, not inside a pipeline, a redirection or
a `&&` chain — including `cd <dir> && …`: the PreToolUse hook that supplies the
ids appends them to the end of the command string. Leading
`GIT_DIR=`/`GIT_WORK_TREE=` assignments are allowed, and are the way to commit
in a linked worktree. A human commit gets no trailer and says nothing of its
own.
