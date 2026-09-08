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
│   └── hooks.json               agy 的 hook 設定
│
├── .claude/                  Claude Code 專用
│   ├── settings.json            Claude 的 hook 設定
│   ├── commands/<name>.md       斜線指令（只有 Claude 支援專案層）
│   ├── memory/                  記憶（不進版控）
│   ├── skills -> ../.agents/skills
│   └── hooks  -> ../.agents/hooks
│
└── script/
    ├── ci/ci.sh              CI 檢查（每個 PR 都跑）
    ├── setup-memory-link.sh
    └── verify-agents.sh
```

**沒有 `.codex/`、`.gemini/`** —— 實測拿掉後兩者功能完全不變。

## 誰吃得到什麼（全部實測）

| 資產 | Claude Code | Codex | agy |
|---|---|---|---|
| **skills** | 讀 `.claude/skills/`，**不讀 `.agents/`** → 靠 symlink | 原生讀 `.agents/skills/` | 原生讀 `.agents/skills/`（headless 需 `--add-dir`） |
| **rules** | 只讀 `CLAUDE.md` → symlink 到 `AGENTS.md` | 讀 `AGENTS.md` | 讀 `AGENTS.md` |
| **hooks** | `.claude/settings.json` | **沒有 hook 機制** | `.agents/hooks.json` |
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
| `.claude/settings.json`、`.claude/commands/` | 逐字對話紀錄、各工具本地狀態 |
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
- **hook** —— `hook-probe.log` 出現新行

> **為什麼要有「註冊」這一項**:只看「使用」會誤判。實測中 Claude Code 在缺少
> `.claude/skills` 的情況下，用 `grep -rn "PROBE" .` 搜到檔案再讀出來，
> 一樣吐得出驗證字串 —— 看起來通過，實際上共用機制根本沒生效。

## 第三方技能

`.agents/skills/` 底下的技能由 [`skills`](https://skills.sh) CLI 安裝，
出處與清單見 [SKILLS.md](SKILLS.md)，版本鎖在 `skills-lock.json`。

```bash
npx skills@latest add <owner>/<repo> --skill <name>
npx skills@latest experimental_install    # clone 後還原全部技能
```

> `--skill` **每個技能要一個旗標**，逗號分隔會被當成單一名稱而找不到。

## 參考

- [Claude Code — Skills](https://code.claude.com/docs/en/skills)
- [Codex — Build skills](https://developers.openai.com/codex/skills)
- [Codex — Custom Prompts](https://developers.openai.com/codex/custom-prompts)
- agy — `~/.gemini/antigravity-cli/builtin/skills/agy-customizations/`（隨 binary 附的官方文件）
