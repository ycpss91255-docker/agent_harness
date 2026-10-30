# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps
those roles to the label strings actually used in this repo's tracker, and
documents the one further state role this repo adds on top of them, for six
state labels in total.

This repo uses the **canonical names verbatim**: every label string equals
its role name, so nothing has to be translated when a skill names a role.
The sixth state role, `needs-decision`, is local to this repo: no skill names
it, so `/triage` will never apply it on its own, and a human has to.

| Label in mattpocock/skills | Label in our tracker | Meaning                                                                        |
| -------------------------- | -------------------- | ------------------------------------------------------------------------------ |
| `needs-triage`             | `needs-triage`       | Maintainer needs to evaluate this issue                                         |
| `needs-info`               | `needs-info`         | Waiting on reporter for more information                                        |
| `ready-for-agent`          | `ready-for-agent`    | Fully specified, ready for an AFK agent                                         |
| `ready-for-human`          | `ready-for-human`    | Requires human implementation: judgment, external access, manual test           |
| `wontfix`                  | `wontfix`            | Will not be actioned                                                            |
| _(no skill role)_          | `needs-decision`     | Evaluated; waiting on a maintainer decision, not information or implementation   |

`needs-decision` is not a second spelling of `needs-triage`. `needs-triage` is
intake: nobody has looked at the issue yet. `needs-decision` is post-intake:
someone has looked, the issue is understood, and what it is blocked on is a
judgement call — not missing information (`needs-info`) and not implementation
capacity (`ready-for-human`, where the call is already made). The one-state
rule still holds, so applying `needs-decision` means removing `needs-triage`
from that issue rather than carrying both.

## Divergence from other `ycpss91255-docker` repos

The sibling repo `ycpss91255-docker/base` has since adopted this vocabulary.
All twelve of this repo's label strings exist in `base` under the same name
and the same colour, and seven are identical in description as well:
`needs-triage`, `needs-info`, `ready-for-human`, `needs-decision`, `wontfix`,
`dependencies` and `github_actions`. `base` also carries none of GitHub's
stock default set — `duplicate`, `invalid`, `question`, `good first issue`,
`help wanted` — so `question` is absent there too and cannot be mistaken for
a deliberate `needs-info` synonym.

What still differs is description text on five shared strings, plus two labels
`base` carries and this repo does not.

- Same name and colour, different description: `bug` (`d73a4a`),
  `documentation` (`0075ca`), `enhancement` (`a2eeef`), `backlog` (`666666`)
  and `ready-for-agent` (`0E8A16`). `base` keeps GitHub's stock wording for
  the three category labels where this repo rewrote all three; `backlog` is
  "Deliberately not scheduled" here against "Tracked for later; deferred —
  not actively worked on right now" there; and `ready-for-agent` here reads
  "Spec is complete: seams, first slice, gate, bound" against "Spec is fully
  specified and ready for an agent to implement" there.
- `base`-only: `upstream` (`d4c5f9`, "Blocked on / tracking an upstream
  project fix"), and `triage` (`ededed`) with an **empty** description.
  `triage` is a leftover, not a second spelling of `needs-triage` — `base`
  carries `needs-triage` itself, with this repo's exact description — so do
  not read `triage` as a state.

A shared label string is still not a shared label: where the two repos
disagree they disagree in the description, so read that rather than the
string. The exception is Dependabot's own `dependencies` and `github_actions`,
which Dependabot creates rather than a maintainer: this repo and `base` carry
both with identical name, colour and description.

`base` carries `needs-decision` too, so the sixth state role is local to this
repo only against `ycpss91255-research/vendor_kit` — the next section — and
not against `base`.

`question` does not exist in this repo at all: `needs-info` covers it, and two
labels for one state only invites drift.

```
$ gh label list -R ycpss91255-docker/agent_harness --json name,color,description
$ gh label list -R ycpss91255-docker/base --json name,color,description
```

Verified 2026-10-09. The 2026-09-08 revision of this section described `base`
as not having adopted the vocabulary at all, as carrying GitHub's full stock
defaults, and as having `wontfix` for its only identical label; `base`'s
labels have changed since and none of that holds.

## `needs-decision` is local to this repo

`ycpss91255-research/vendor_kit`, the reference implementation of this
vocabulary, carries the five canonical roles and does **not** carry
`needs-decision`. Do not assume an issue there can express "blocked on a
decision"; in that repo such an issue sits under `needs-triage` or carries no
state label at all.

```
$ gh label list -R ycpss91255-research/vendor_kit
```

Verified 2026-09-08: `needs-triage`, `needs-info`, `ready-for-agent`,
`ready-for-human`, `wontfix` — plus `backlog` and `upstream`, and no
`needs-decision`.

## Category labels

`bug`, `documentation`, `enhancement` — the org convention. `/triage`'s two
category roles map to `bug` and `enhancement`; `documentation` is a third
category the org uses for docs-only work.

## Labels that are NOT triage states

`backlog` is orthogonal to the state machine: an issue can be
`ready-for-agent` and `backlog` at once. `/triage` must not treat `backlog` as
a state role, and must not remove it when transitioning state.

`dependencies` and `github_actions` are Dependabot's own labels, applied to
its pull requests. They are not triage vocabulary and `/triage` should ignore
them.

The unused GitHub defaults (`duplicate`, `invalid`, `question`,
`good first issue`, `help wanted`) were deleted from this repo. Every label
that remains is read by someone: the skills, the org's own conventions, or
Dependabot. Don't re-add one without a reader.
