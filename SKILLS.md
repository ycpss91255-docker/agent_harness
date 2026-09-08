## 第三方技能出處

`.agents/skills/` 底下除了 `probe-marker`（本 repo 的驗證探針）之外，
全部由 [`skills`](https://skills.sh) CLI 從下列來源安裝，授權皆為 MIT。
版本以 `skills-lock.json` 的內容雜湊記錄。

### [ayghri/i-have-adhd](https://github.com/ayghri/i-have-adhd) — 1 個

```
i-have-adhd
```

### [humanlayer/skills](https://github.com/humanlayer/skills) — 1 個

```
show-me
```

### [mattpocock/skills](https://github.com/mattpocock/skills) — 25 個

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

安裝或更新:

```bash
npx skills@latest add <owner>/<repo> --skill <name>   # 每個技能一個 --skill，逗號分隔無效
npx skills@latest update                              # 依 skills-lock.json 更新
npx skills@latest experimental_install                # clone 後還原全部技能
```
