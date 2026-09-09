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

Two sibling repos in the org, `ycpss91255-docker/base` and
`ycpss91255-docker/docker_harness`, have not adopted this vocabulary at all.
Neither carries `needs-triage`, `needs-info` or `ready-for-human` under any
spelling. Both still carry GitHub's full stock default set — `duplicate`,
`invalid`, `question`, `good first issue`, `help wanted` — with GitHub's stock
descriptions.

- `question` in both repos is described "Further information is requested",
  GitHub's own wording. It is an undeleted default, **not** a deliberate
  `needs-info` synonym, and must not be read as one.
- `ycpss91255-docker/base` does additionally carry a genuinely custom `triage`
  label ("Newly filed; awaiting review / categorization (needs a maintainer or
  bot to sort)"), which is not one of GitHub's defaults. That one is
  deliberate and does line up with the `needs-triage` role.
- `ycpss91255-docker/docker_harness` has no custom triage label at all.

Where the same label string does appear in more than one repo, the description
is written per repo, and the colour is shared only most of the time: `backlog`
is `666666` here and in `base` but `ededed` in `docker_harness`, with three
different descriptions. The exception is Dependabot's own `dependencies` and
`github_actions`, which Dependabot creates rather than a maintainer: this repo
and `base` carry both with identical name, colour and description, and
`docker_harness` carries neither.

Comparing this repo against both `ycpss91255-docker/base` and
`ycpss91255-docker/docker_harness`: `ready-for-agent` and the category labels
`bug`, `documentation` and `enhancement` match in name and colour but differ
in description in every case. For instance `ready-for-agent` here reads "Spec
is complete: seams, first slice, gate, bound", while in both sibling repos it
reads "Spec is fully specified and ready for an agent to implement". `wontfix`
is the only label that is genuinely identical — name, colour and description —
across all three repos.

When reading an issue **in `base`**, treat `triage` as `needs-triage`. In
`docker_harness` there is no label for the `needs-triage` state, so an
untriaged issue there is simply one carrying no state label. In neither repo
is there any label for the `needs-info` state: an issue waiting on its
reporter is not distinguishable by label there, and seeing `question` on it
tells you nothing about that.

`question` does not exist in this repo at all: `needs-info` covers it, and two
labels for one state only invites drift.

```
$ gh label list -R ycpss91255-docker/base
$ gh label list -R ycpss91255-docker/docker_harness
```

Verified 2026-09-08: every claim above holds, with the colour and Dependabot
caveats already noted. `docker_harness` is scheduled for retirement, so expect
this section to outlive the repo it describes.

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
