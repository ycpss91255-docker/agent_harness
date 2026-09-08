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

```bash
# one --skill flag per skill; a comma-separated list is read as a single name
npx skills@latest add <owner>/<repo> --skill <name> --skill <name>

npx skills@latest update                 # update against skills-lock.json
npx skills@latest experimental_install   # restore every skill after a clone
npx skills@latest list                   # show what is installed
```
