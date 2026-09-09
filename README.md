# agent — 三個 CLI agent 的共用骨架

同一份技能與專案指示，讓 **Claude Code**、**OpenAI Codex**、
**agy (Antigravity / Gemini)** 三邊都吃得到。

結構不是照設定檔猜的，是**逐項實測 + 對照官方文件**得出的。
每一條結論下面都附了驗證方式，隨時可重跑:`script/verify-agents.sh`

## 結構

```
agent/
├── AGENTS.md                 專案指示（單一事實來源）
├── CLAUDE.md -> AGENTS.md    Claude Code 不讀 AGENTS.md，必須有這條
│
├── .agents/                  真正共用的資產
│   ├── skills/<name>/SKILL.md    三個 agent 都讀得到
│   ├── hooks/*.sh               hook 腳本，Claude 與 agy 共用
│   ├── scripts/gh-issue.sh      init.sh 由 dist/agents/scripts/ 接過來
│   └── hooks.json               agy 的 hook 設定
│
├── .claude/                  Claude Code 專用
│   ├── settings.json            Claude 的 hook 設定
│   ├── commands/<name>.md       斜線指令（只有 Claude 支援專案層）
│   ├── memory/                  記憶（不進版控）
│   ├── skills -> ../.agents/skills
│   └── hooks  -> ../.agents/hooks
│
├── .codex/                  Codex only
│   └── hooks.json              Codex's hook config (one of two files Codex
│                                reads project hooks from; the other is
│                                .codex/config.toml, unused here)
│
└── script/
    ├── ci/ci.sh              CI 檢查（每個 PR 都跑）
    ├── gh-issue.sh -> ../dist/agents/scripts/gh-issue.sh
    ├── setup-memory-link.sh
    └── verify-agents.sh
```

**沒有 `.gemini/`** —— 實測拿掉後功能完全不變。

**`.codex/` — the decision was right when it was taken, and its premise has
since expired.** This repo carried no `.codex/` directory, on the measured
ground that removing it changed nothing. That measurement was correct and still
is for what it covered: skills, prompts and rules load from `.agents/` and
`AGENTS.md` with no `.codex/` present. What changed underneath it is that
`.codex/` became the directory Codex reads **project hooks** from. Re-measured
on 2026-09-09 with codex-cli 0.153.2: a hook wired in `<repo>/.codex/hooks.json`
fires. So the directory is back, carrying exactly one file, and the record is
"re-measure, the ground moved" rather than "this was a mistake".

The directory is the boundary; the filename is not. `hooks/list` reports
`source: "project"` for hooks declared in **either** `<repo>/.codex/hooks.json`
**or** `[[hooks.*]]` blocks in `<repo>/.codex/config.toml`, each entry naming
its own file as `sourcePath` (measured 2026-09-09, both layers, same repo).
What is measured as *not* read is `.agents/`: the identical file placed at
`<repo>/.agents/hooks.json` produces no entry at all. This repo uses
`hooks.json` because it is the smaller file and needs no TOML; that is a
preference, not the only path that would work.

## 誰吃得到什麼（全部實測）

| 資產 | Claude Code | Codex | agy |
|---|---|---|---|
| **skills** | 讀 `.claude/skills/`，**不讀 `.agents/`** → 靠 symlink | 原生讀 `.agents/skills/` | 原生讀 `.agents/skills/`（headless 需 `--add-dir`） |
| **rules** | 只讀 `CLAUDE.md` → symlink 到 `AGENTS.md` | 讀 `AGENTS.md` | 讀 `AGENTS.md` |
| **hooks** | `.claude/settings.json` | `.codex/hooks.json` or `.codex/config.toml` — never `.agents/`, and behind two trust gates | `.agents/hooks.json` |
| **commands** | `.claude/commands/` | 不支援專案層 | 不支援 |
| **memory** | `.claude/memory/` | 無對應機制 | 無對應機制 |

所以 `.agents/` 底下只放**真正三邊共用**的東西(skills、hook 腳本)；
Claude 專屬的(commands、memory、settings.json)一律放 `.claude/`。

## 每個 agent 的注意事項

### Claude Code

- **不讀 `.agents/`**。官方文件明寫「Claude Code reads `.claude/skills/` only,
  not `.agents/skills`」，所以 `.claude/skills` 那條 symlink 是必要的。
- 會跟隨 symlink，且同一目標從多處可達時只載入一次。
- **`CLAUDE.md` 不能省**。實測拿掉後它讀不到 `AGENTS.md` 的內容。

### Codex

- 原生掃 `.agents/skills`，從 cwd 往上走到 repo root。支援 symlink。
- **需要是 git repo**，否則報 `Not inside a trusted directory`
  （或加 `--skip-git-repo-check`）。
- `.codex/skills` 是**舊路徑**，官方已改用 `.agents/skills`。
- **沒有專案層斜線指令**。自訂 prompt 只吃 `~/.codex/prompts/`，
  而且官方標為 deprecated:「if you want to share a prompt or want Codex to
  implicitly invoke it, **use skills instead**」。
- **Project hooks exist, and `.codex/` is where they are read from**
  (codex-cli 0.153.2, measured 2026-09-09) — `<repo>/.codex/hooks.json`, which
  is what this repo ships, and equally `[[hooks.*]]` blocks in
  `<repo>/.codex/config.toml`; `hooks/list` returns both with
  `source: "project"`. The same file placed under `.agents/` is not picked up.
  Config shape and payloads are Claude Code's: `PreToolUse` with `matcher` +
  `hooks`, `tool_name` `"Bash"`, `tool_input.command`, and a
  `hookSpecificOutput.permissionDecision` reply. Five things differ and each one
  can wire a hook that never runs:

  - The command runs **through a shell**, but from the **session's working
    directory**, not the repo root, and Codex sets no project-directory
    variable of its own. A bare `./…` path works from the root and breaks one
    directory down; `"$(git rev-parse --show-toplevel)/…"` works from any depth.
  - **The project must be trusted** in `~/.codex/config.toml`
    (`[projects."<path>"] trust_level = "trusted"`), and the entry has to name
    the **repo root exactly**: trust does not descend, so an entry for a parent
    directory leaves a repo nested under it untrusted. A `-c` override does not
    do it either — trust is read from the file, not the merged config.
  - **Each hook must be reviewed.** A fresh clone's hooks are `untrusted` and
    do not run; the review is a TUI flow, and the recorded hash changes
    whenever the hook config changes. Non-interactive runs need
    `--dangerously-bypass-hook-trust`.
  - Under `codex exec` **both gates fail silently**: no hook line, no warning,
    nothing runs. The trust gate is *not* silent everywhere else — the
    app-server and the TUI print an `ERROR` naming the untrusted `.codex`
    folder and load no project hooks from it. Adding `.codex/` to a repo that
    is not a trusted project is therefore visible in every entry point except
    the one this repo's own checks use. **This repo is such a repo**: nothing
    under `~/.codex/config.toml` names its root, so the `.codex/hooks.json` it
    now ships is inert here until someone adds the entry.
  - `handlerType: command` is the only handler **shown to work**, which is not
    the same as the only one Codex accepts. `prompt` and `agent` are refused
    outright ("prompt hooks are not supported yet"). `mcp_tool` is parsed,
    listed as an enabled project hook and actually dispatched — it failed here
    only because the MCP server it named does not exist, so it is neither
    proven to work nor refused. Related trap: the config parser takes only
    `command|mcp_tool|prompt|agent`, and rejects `mcpTool` — the spelling
    `hooks/list` itself prints back — as an unknown variant, which drops
    **every** hook in that file, reported as a `hooks/list` warning and
    nowhere at all under `codex exec`.

  Verified 2026-09-09: Codex **acts on** the deny. `codex exec` with both gates
  cleared printed `hook: PreToolUse Blocked` and `Command blocked by PreToolUse
  hook: …`, from the repo root and from a subdirectory, and a `gh` stub first on
  `PATH` recorded zero invocations — the command did not run. This paragraph
  said "not verified" until that run; the difference is a demonstration, not a
  reading of the binary.

### agy (Antigravity)

- **headless 模式一定要 `--add-dir`，互動模式不用**:

  ```bash
  agy                        # 互動:自動掃描到 .agents/，不必加旗標
  agy --add-dir "$PWD" -p "..."   # headless:一定要加
  ```

  headless 不帶旗標的話 skills 只剩內建兩個，log 顯示
  `loaded 0 named hooks from 0 hooks.json file(s)`。
  值得注意的是 log 裡 `workspaceDirs` **本來就有 cwd** —— 它知道你在哪，
  但 print 模式不會主動掃描，必須明確加入。
  文件寫的「從 cwd 往上遍歷」只在互動模式成立。
- hook 的**工作目錄是 `hooks.json` 所在的 `.agents/`**，
  所以命令寫 `./hooks/x.sh`，不是 `./.agents/hooks/x.sh`。
- `PreInvocation` / `PostInvocation` / `Stop` 是 **flat 結構**（直接放 handler 物件）；
  只有 `PreToolUse` / `PostToolUse` 才用 `matcher` + `hooks` 包裝。
- 客製化類型只有 Rules / Skills / Plugins / Hooks / MCP，**沒有 commands**。

## 進版控的 / 不進版控的

| 進 | 不進 |
|---|---|
| `.agents/` 的 skills、hooks、hooks.json | `.claude/memory/` 整個目錄 |
| `.claude/settings.json`、`.claude/commands/`、`.codex/hooks.json` | 逐字對話紀錄、各工具本地狀態 |
| `AGENTS.md` 與 `CLAUDE.md` symlink | `hook-probe.log`（測試產物） |

## 記憶

`.claude/memory/` **整個目錄不入庫**，clone 後由腳本建立並接上
`~/.claude/projects/<路徑 slug>/memory`:

```bash
script/setup-memory-link.sh
script/setup-memory-link.sh --dry-run    # 先看會做什麼
```

冪等:已接好就跳過；目標不對會替換；本地有新內容會拒絕並要你先合併，
`--force` 則先備份再換。

## 驗證

有兩條路徑，測的東西不同:

| | `script/ci/ci.sh` | `script/verify-agents.sh` |
|---|---|---|
| 跑在哪 | 本機 + 每個 PR（GitHub Actions） | **只有本機** |
| 測什麼 | 這個結構賴以成立的不變條件 | 三個 agent 實際讀不讀得到 |
| 需要什麼 | shellcheck、docker、python3 | 三個 CLI 與各自的 API 憑證 |

`verify-agents.sh` 進不了 CI 就是因為最後那欄 —— 它要真的叫起三個 agent。

### `script/ci/ci.sh` —— PR 的守門員

```bash
script/ci/ci.sh all          # 或 lint / actionlint / json / frontmatter / structure / lock
```

每一項都對應這個 repo 真的壞過的地方:

| 檢查 | 擋掉什麼 |
|---|---|
| `structure` | symlink 斷掉或指錯 → Claude Code **靜默**看不到共用技能 |
| `json` | `.agents/hooks.json` 結構錯 → 只在 agy 的 log 裡報，輸出完全正常 |
| `frontmatter` | `SKILL.md` 缺 `name`/`description` → 三個 agent 都不註冊，無聲失敗 |
| `lock` | 技能目錄沒進 `skills-lock.json` → clone 後還原不了 |
| `lint` | shellcheck 兩個腳本目錄 |
| `actionlint` | `runs-on` 打錯字**不會失敗，而是讓 job 永遠排隊** |

檢查清單是 `ci.sh` 裡的 `CHECKS=(...)` 陣列，`all` 由它推導、workflow 只跑
`ci.sh all` —— 加一項檢查只改一個地方，立刻對 PR 生效。

### `script/verify-agents.sh` —— 三個 agent 真的讀得到嗎

```bash
script/verify-agents.sh all       # 或 claude / codex / agy
```

三項獨立判定:

- **註冊** —— 在「禁止任何工具呼叫」的前提下，agent 列得出 `probe-marker`
  → 證明是原生載入
- **使用** —— 吐得出只寫在 `SKILL.md` 內文的字串
- **hook** —— `hook-probe.log` 出現一行，同時帶著**這一次執行的 nonce**
  和 `agent=<受測的那個 agent>`；Codex 這一項是**反過來判**，見下。

> **為什麼要有「註冊」這一項**:只看「使用」會誤判。實測中 Claude Code 在缺少
> `.claude/skills` 的情況下，用 `grep -rn "PROBE" .` 搜到檔案再讀出來，
> 一樣吐得出驗證字串 —— 看起來通過，實際上共用機制根本沒生效。

> **為什麼「出現新行」不算數**:舊的斷言是 `[ -s "$LOG" ]` —— 檔案不是空的。
> probe 寫出來的每一行長得都一樣（`agent=unknown`，因為當時根本沒有人設過
> `AGENT_NAME`），所以它真正說的只是「最近幾秒內有人在這個 repo 跑過 hook」。
> 這台機器同時開著好幾個 Claude Code session 對著這個 repo:讓腳本完全不跑、
> 空等 45 秒，log 自己就多了 7 行。而**完全沒有接上 probe hook 的 Codex 也照樣
> PASS** —— 一項這棵樹裡不可能成立的檢查，通過了。

現在有兩個欄位讓它真的有意義，而且在 probe 裡兩個都是選填的 —— `test_probe.sh`
平常工作時每一次 Bash 呼叫都會觸發，那條路徑必須安靜、快、而且成功，所以兩個欄位
都給了「有定義但沒用」的預設值，而不是缺了就報錯:

| 欄位 | 從哪來 | 少了它會怎樣 |
|---|---|---|
| `AGENT_NAME` | `.claude/settings.json` 與 `.agents/hooks.json` 裡命令的環境變數前綴（兩邊都是用 shell 跑 hook 命令，所以前綴這個寫法兩種格式都吃） | 每一行都說不出是誰寫的 |
| `PROBE_NONCE` | 每次探測現產的隨機碼，export 到腳本拉起的那個 agent process 上，再由它生出的 hook 繼承 | 分不出這次執行和同一個 repo 裡另一個 Claude Code session —— 兩邊都寫 `agent=claude`，看時間也分不出來 |

也因為有 nonce 可以 grep，**log 不再事先清空**。以前那句 `: > "$LOG"` 只是把別的
session 幾秒前寫的行洗掉，換不到任何東西。

> **The Codex row here is judged inverted, not skipped — and the inversion is
> new.** It was added together with the Codex hook wiring, in the same change;
> it was not carried over from before it. Until then Codex ran the identical
> `[ -s "$LOG" ]` assertion as the other two agents, which is exactly how an
> agent with no probe hook wired came out PASS on another session's lines.
> Why it exists now is narrow: **this repo wires no probe hook for Codex** —
> `.codex/hooks.json` does not name `test_probe.sh` — so no line the probe
> writes can be attributable to Codex, and the assertion "**no** line carries
> this run's nonce" is one that can actually fail. That is a much smaller claim
> than "Codex has no hook mechanism at all", which the same change disproved by
> measurement (see the Codex section above). The output labels it `inverted` so
> that nobody reads it as "Codex ran a hook". It costs almost nothing and still
> catches two things: a probe hook wired for Codex behind our backs, or the
> nonce leaking out of the Codex process into another agent's hook.

判定結果會回到 exit code 上:任何一項 FAIL → `exit 1`，全過 → `exit 0`，target
打錯 → `exit 2`。舊版一律 `exit 0`，那不是決定，是 dispatch 最後一個 `command -v`
順手留下的狀態 —— 於是「到底過了沒」只能靠人去讀 stdout，對呼叫端沒有用。
CLI 沒裝的那個 agent 會印 `--- skipped` 並且不算失敗，而不是像以前那樣整段消失。

> 但「註冊」那一項靠的是模型真的聽話「不要執行任何命令、不要讀任何檔案」——
> 那是指示，不是強制。所以 exit 非零是**該去讀輸出**的理由，不等於結構壞了。

## 第三方技能

`.agents/skills/` 底下的技能由 [`skills`](https://skills.sh) CLI 安裝，
出處與清單見 [SKILLS.md](SKILLS.md)，版本鎖在 `skills-lock.json`。

```bash
npx skills@1.5.24 add <owner>/<repo> --skill <name>
npx skills@1.5.24 experimental_install    # clone 後還原全部技能
```

> `--skill` **每個技能要一個旗標**，逗號分隔會被當成單一名稱而找不到。

## 參考

- [Claude Code — Skills](https://code.claude.com/docs/en/skills)
- [Codex — Build skills](https://developers.openai.com/codex/skills)
- [Codex — Custom Prompts](https://developers.openai.com/codex/custom-prompts)
- agy — `~/.gemini/antigravity-cli/builtin/skills/agy-customizations/`（隨 binary 附的官方文件）
