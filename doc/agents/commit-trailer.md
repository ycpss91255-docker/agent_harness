# The Assisted-by commit trailer

A commit made by an agent carries one trailer saying so. A commit made by a
person carries nothing.

```
Assisted-by: claude-code session:d5c2a46d agent:a021dc30
Assisted-by: claude-code session:d5c2a46d agent:main
Assisted-by: codex session:01a07ed9 agent:b7f21e44
```

Produced by `.agents/scripts/assisted-commit.sh`, which is `git commit` with the
trailer added. It claims three things for itself -- `--print-command`, `-h` and
`--help`, and only where they come *before* the first argument it does not
recognise -- plus the `--assisted-<field>=` arguments the hook appends to the
tail. Everything else is forwarded to git untouched, and the `--trailer` it adds
goes in front of the caller's arguments, so a trailing `--` still terminates the
flags it was written to terminate.

```
.agents/scripts/assisted-commit.sh -m "hooks: wire the tagger for Codex"
.agents/scripts/assisted-commit.sh --print-command -m "..."   # show, run nothing
```

## The format

Three fields, in this order: the tool, the session, the agent.

| field | value |
|---|---|
| tool | `claude-code` or `codex` |
| session | the agent session id, first 8 characters |
| agent | the subagent id, first 8 characters, or `main` from the main thread |

Ids are truncated like a git short hash. A prefix is still enough to find the
full id locally, and the untruncated pair makes the line unreadable.

`main` is a word, not an id. It is written out whole -- nothing truncates it to
eight characters and no check written for the shape of an id is applied to it --
and it says the commit came from an agent's main thread rather than from one of
its subagents. Every commit an agent makes therefore carries all three fields.

**No model, no CLI version.** Both were considered and dropped. Claude Code
cannot report the model it is running, so the field would be present for one
tool and absent for the other, and an asymmetric field is worse than no field:
a reader cannot tell "this tool does not report it" from "this commit did not
have one".

**`Assisted-by:`, not `Co-Authored-By:`.** Apache Calcite, JMeter and Cloudberry
converged on this key, and the reason is mechanical rather than stylistic. git
and GitHub read every name in a `Co-Authored-By` trailer as an *author* of the
commit, so a tool listed there asserts authorship. `Assisted-by:` asserts what
actually happened, and no tool of git's reads it as a person.

## What each situation produces

| situation | trailer | stderr |
|---|---|---|
| a person commits, no agent anywhere | none | nothing, exit 0 |
| an agent subagent commits | `Assisted-by: claude-code session:d5c2a46d agent:a021dc30` | nothing |
| an agent main thread commits | `Assisted-by: claude-code session:d5c2a46d agent:main` | nothing |
| an agent commits, the hook did not run | `Assisted-by: claude-code` | loud |
| an agent commits, one field unusable | that field omitted | loud |
| git older than 2.32 | none | loud |

Three rules decide the table.

**A field that is genuinely unavailable is omitted, never filled in.**
`agent:unknown` would be worse than absence, because `git log --grep` cannot
tell a placeholder from a real value, while an absent field is unambiguous. That
is why an unusable session id costs the session field rather than a stand-in.

**The main thread is not an unavailable field, it is a state with a name.** It
has no agent id -- Claude Code's payload carries `agent_id` only from inside a
subagent, and it is absent for the main thread by design rather than by failure
-- but *which thread committed* is known, so the field says `main`. It is a
statement, not a placeholder: `git log --grep 'agent:main'` selects exactly the
main-thread commits, and the alternative, dropping the field, made a main-thread
commit and a commit whose agent id could not be read look the same in the log.

**A broken mechanism is loud, and still commits.** Refusing would turn a wiring
problem into lost work, and a silently shortened trailer would let a hook that
stopped firing look exactly like normal operation.

## How the ids get there

They are not readable from the shell an agent runs a command in. They arrive in
the wrapper's own argv, put there by the PreToolUse hook
`.agents/hooks/tag_assisted_commit.sh`, which rewrites the command that is about
to run:

```
.agents/scripts/assisted-commit.sh -m "msg"
.agents/scripts/assisted-commit.sh -m "msg" --assisted-tool=claude-code \
    --assisted-session=<id> --assisted-agent=<id>
```

`hookSpecificOutput.updatedInput` is Claude Code's own documented field --
"Modified tool input (PreToolUse only)". Payload and command are correlated by
the runtime, not by any key this repo computes, so concurrency is a non-issue by
construction: three concurrent subagents were measured getting three distinct,
correct agent ids in three real commits. Every state-file scheme needs a shared
key and there is none -- `tool_use_id` is in the payload and nowhere in the
command's environment.

**Appended, never prepended.** Permissions are re-evaluated against the
rewritten command. Rewriting to `export X=...; ./assisted-commit.sh ...` was
measured being denied under an allowlist of `Bash(./assisted-commit.sh:*)` that
the same command passed with the hook removed, because the prefix had changed.
Appending leaves the prefix alone.

**The sentinel.** When the runtime reports no agent id, the hook injects
`--assisted-agent=main` rather than injecting nothing. Without it, "the main
thread has no agent id" and "the hook never ran" are the same observation, and
the first has to be silent while the second has to be loud. The wrapper renders
it, so the three states are told apart by reading the commit and not only by
having watched stderr when it was made.

`main` cannot be mistaken for a truncated id. Claude Code's agent ids are `a`
followed by 16 hex digits -- 2443 distinct ids read out of local transcripts,
every one of that shape -- `m` is not a hex digit, and ids reach the trailer cut
to eight characters while `main` is four. **What no layer here can tell apart**
is a runtime that reports an `agent_id` of literally `main`: the hook's id
pattern accepts that string like any other, so it would be injected and rendered
exactly as the sentinel is. No measured id is `main`, and for Codex the subagent
id shape is unconfirmed altogether (below), so this is recorded rather than
defended against.

**Invoke the wrapper as a plain command.** The fields are appended to the end of
the command string, so they only reach the wrapper's argv when the end of the
string is the wrapper's argument list. The hook therefore refuses to rewrite a
command carrying `; | & < > ( )` a backtick, `$(` or a newline *outside quotes*
-- a pipeline, a chain, a redirection. The scan is quote-aware rather than a
grep, because commit messages are made of those characters and
`-m "hooks: handle > and |"` still has to be tagged. A refused rewrite costs a
loud warning, never a wrong trailer and never a lost commit.

**In a linked worktree, point git at it -- do not `cd` into it.** This is the
one shape of the rule above that an agent reaches for by reflex, and it bit two
agents working in this repo on the same day. An agent's shell resets its working
directory between calls, so the obvious way to commit in a worktree is
`cd <worktree> && assisted-commit.sh ...` -- and that `&&` is exactly what the
scan refuses. The hook says nothing, the ids never reach argv, and the commit
lands with a one-field trailer and the loud warning:

```
$ cd <worktree> && .agents/scripts/assisted-commit.sh --print-command -m "docs: state the trailer format"
git commit --trailer 'Assisted-by: claude-code' -m 'docs: state the trailer format'
assisted-commit.sh: the Assisted-by trailer is incomplete: nothing was injected
  an agent is running this commit (claude-code), but the PreToolUse hook that
  supplies the session and agent ids did not rewrite the command, so
  those two fields cannot be filled in. [...]
```

The way through is **leading `GIT_DIR=` and `GIT_WORK_TREE=` assignments**,
which the matcher allows by construction: it looks for the wrapper as the first
word *after any run of `VAR=value` assignments*, so the wrapper is still the
command the string begins with and its argument list is still the string's end.

```
$ GIT_DIR=<wt>/.git GIT_WORK_TREE=<wt> .agents/scripts/assisted-commit.sh --print-command -m "docs: state the trailer format"
git commit --trailer 'Assisted-by: claude-code session:d5c2a46d agent:a021dc30' -m 'docs: state the trailer format'
```

Three fields, and nothing on stderr. For a worktree of the repo the agent is
already in, `GIT_DIR=<repo>/.git/worktrees/<name>` is the same assignment by its
other name. `--print-command` is the cheap way to check before committing: it
prints the `git commit` it would run and commits nothing.

**The session id is not read from the environment**, although `$CLAUDE_CODE_SESSION_ID`
is there. A second, silent channel would repair the exact symptom the loud path
exists to reveal, and it is Claude-Code-only, which would make Codex the
asymmetric case for no gain.

**The session name is not used either, and this is settled.** Claude Code keeps
it at `~/.claude/sessions/$CLAUDE_PID.json` as `name`, beside `sessionId`, and
it was considered as a more readable substitute for the truncated id. It is a
user-set label rather than an identifier: it can be changed mid-session, nothing
makes it unique, and it can contain non-ASCII characters, which this org's
English-only rule for git artifacts forbids. The id stays.

## Whose values reach the trailer

The hook's. The fields travel in argv, which is a channel anyone invoking the
wrapper can write to, so the wrapper decides between them **by position**:

* it reads the fields **right to left** and keeps the first value it sees for
  each, and the hook's values are the rightmost because the hook appends;
* the hook's group is taken to start at its `--assisted-tool=`, which it always
  emits first, so a field to the *left* of that cannot fill one the hook left
  out either;
* anything it drops that way is reported on stderr, because the case worth
  noticing is an agent replaying a command it read in its own transcript, where
  the discarded id was real and belonged to somebody else.

The hook helps from its own side: a command that already carries **any**
`--assisted-<field>=` is left alone rather than tagged again, so the hook never
builds a command with two sets of ids in it.

**A caller cannot be forbidden from writing these**, and the wrapper does not
pretend to forbid them. argv is the hook's only channel -- an environment
variable would have to be prepended to the command, and that changes the prefix
a permission allowlist matches -- so the wrapper cannot tell the hook's use of
that channel from anybody else's. Position is what it can make authoritative,
and it does. That is also what lets `script/ci/ci.sh` drive every path here
without a live hook, through the same channel the hook uses, instead of through
a test-only door that would then exist in production too.

What remains, and is not fixable at this layer: a caller that supplies a full,
well-formed set with no hook injection to compare against gets that set in the
trailer. Nothing at this layer can distinguish it -- and the same caller could
have run `git commit --trailer` directly. The property held here is the narrower
and achievable one: **a caller cannot pre-empt the hook.**

## Codex

Same mechanism, with one mandatory difference: **Codex discards an
`updatedInput` that arrives without `permissionDecision: "allow"`** -- measured
as `hook: PreToolUse Failed`, the rewrite dropped, and the original command run
instead. So on Codex the hook also grants permission, which is why its match is
narrow: it emits a decision only for a command whose first word is the wrapper,
only when nothing follows that command, and never on Claude Code, where
`updatedInput` needs no decision and an `allow` would waive a permission prompt
the author is entitled to.

Codex's schemas agree with Claude Code's on the rest: `pre-tool-use` has
`agent_id` as an optional property, `subagent-start` requires it.

**Not confirmed:** a Codex *subagent* `agent_id` at runtime.
`collaboration.spawn_agent` exists but hung repeatedly under `codex exec`. It is
schema-confirmed, not runtime-confirmed, so a Codex subagent commit may land on
the `--assisted-agent=main` path until somebody measures it interactively -- and
that path now writes `agent:main`, which would say "main thread" about a
subagent. Measure it before reading a Codex `agent:main` as a fact.

agy is out of scope: it does not write commits here.

## Where the pieces live

| file | role |
|---|---|
| `.agents/scripts/assisted-commit.sh` | the wrapper: assembles the trailer, commits |
| `.agents/hooks/tag_assisted_commit.sh` | the PreToolUse hook: injects the ids |
| `.claude/settings.json`, `.agents/hooks.json`, `.codex/hooks.json` | wire the hook, one per agent |

Both files are shipped from `dist/` and linked into place by `init.sh`, so the
`.agents/` paths above are the ones to name anywhere -- they are true in a
consumer's repo as well as in this one.

`script/ci/ci.sh check_assisted_commit` drives the whole chain: the hook with
real payloads, the wrapper into a throwaway repo under `/tmp` with `GIT_DIR`
pinned into it, and three negative controls, so an inert wrapper or an inert
hook cannot pass.
