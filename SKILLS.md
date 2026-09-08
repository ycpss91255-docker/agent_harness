# Third-party skills

Everything under `.agents/skills/` except `probe-marker` (this repo's own
verification probe) was installed by the [`skills`](https://skills.sh) CLI
from the sources below. All are MIT licensed.
Versions are pinned by content hash in `skills-lock.json`.

## [ayghri/i-have-adhd](https://github.com/ayghri/i-have-adhd) — 1 skills

```
i-have-adhd
```

## [humanlayer/skills](https://github.com/humanlayer/skills) — 1 skills

```
show-me
```

## [mattpocock/skills](https://github.com/mattpocock/skills) — 25 skills

```
ask-matt
code-review
codebase-design
diagnosing-bugs
domain-modeling
grill-me
grill-with-docs
grilling
handoff
implement
improve-codebase-architecture
prototype
research
resolving-merge-conflicts
setup-matt-pocock-skills
tdd
teach
to-questionnaire
to-spec
to-tickets
triage
wait-what
wayfinder
wizard
writing-for-agents
```

## Installing and updating

The CLI version is pinned too: `@latest` would let a breaking change in the
tool break the documented restore path, and nothing here would record which
version produced `skills-lock.json`.


```bash
# one --skill flag per skill; a comma-separated list is read as a single name
npx skills@1.5.24 add <owner>/<repo> --skill <name> --skill <name>

npx skills@1.5.24 update                 # update against skills-lock.json
npx skills@1.5.24 experimental_install   # restore every skill after a clone
npx skills@1.5.24 list                   # show what is installed
```
