# agent — 三個 CLI agent 的共用骨架

同一份技能／指令／hook／記憶，讓 **Claude Code**、**OpenAI Codex**、
**agy (Antigravity / Gemini)** 三邊都吃得到。

結構不是憑設定檔猜的，是**逐項實測 + 對照官方文件**得出的。
驗證腳本:`scripts/verify-agents.sh`

## 結構

```
agent/
├── AGENTS.md                 專案指示（單一事實來源）
├── CLAUDE.md -> AGENTS.md    Claude Code 不讀 AGENTS.md，必須有這條
│
├── .agents/                  唯一實體。Codex 與 agy 原生就讀這裡
│   ├── skills/<name>/SKILL.md
│   ├── commands/
│   ├── hooks/                hook 腳本
│   ├── hooks.json            agy 的 hook 設定
│   └── memory/               不進版控
│
├── .claude/                  只有 Claude Code 需要這層
│   ├── settings.json         Claude 的 hook 設定
│   ├── skills   -> ../.agents/skills
│   ├── commands -> ../.agents/commands
│   ├── hooks    -> ../.agents/hooks
│   └── memory   -> ../.agents/memory
│
└── scripts/
    ├── setup-memory-link.sh  接 Claude Code 的記憶目錄
    └── verify-agents.sh      驗證三個 agent 讀不讀得到
```

**沒有 `.codex/`、`.gemini/`** —— 實測拿掉後兩者功能完全不變。
`.codex/skills` 是 Codex 的舊路徑，官方已改為 `.agents/skills`。

## 三個 agent 的差異（實測結果）

| 資產 | Claude Code | Codex | agy |
|---|---|---|---|
| **skills** | 讀 `.claude/skills/`，**不讀 `.agents/`** → 靠 symlink | 原生讀 `.agents/skills/` | 原生讀 `.agents/skills/`（headless 需 `--add-dir`） |
| **rules** | 只讀 `CLAUDE.md` → symlink 到 `AGENTS.md` | 讀 `AGENTS.md` | 讀 `AGENTS.md` |
| **hooks** | `.claude/settings.json` | **無 hook 機制** | `.agents/hooks.json` |
| **commands** | `.claude/commands/` | **不支援專案層** | **不支援專案層** |
| **memory** | `scripts/setup-memory-link.sh` 接上 | 未驗證 | 未驗證 |

> **`.agents/commands/` 實際上只有 Claude Code 吃得到。** 實測 Codex 與 agy 在
> 「禁止工具呼叫」的前提下都回答「沒有 ping 這個斜線指令」——它們沒有註冊，
> 先前看似成功是因為 agent 自己去翻檔案。
>
> **記憶目前也只有 Claude Code 接上。** `.agents/memory/` 對另外兩個而言只是
> 一般目錄，「三個 agent 共用記憶」尚未成立。

### 踩過的坑

- **agy headless 要 `--add-dir`**：只靠 cwd 不會觸發 workspace 客製化探索，
  log 會顯示 `loaded 0 named hooks from 0 hooks.json file(s)`。
- **agy 的 hook 路徑相對於 `.agents/`**：文件寫「working directory is set to
  the directory containing hooks.json」，所以寫 `./hooks/x.sh` 而非 `./.agents/hooks/x.sh`。
- **agy 的 `PreInvocation` 是 flat 結構**：不用 `matcher`/`hooks` 包裝，
  只有 `PreToolUse`／`PostToolUse` 才是 grouped。
- **Codex 需要 repo 是 git repo**：否則報 `Not inside a trusted directory`。

## 進版控的 / 不進版控的

| 進 | 不進 |
|---|---|
| `.agents/` 的 skills、commands、hooks、hooks.json | `.agents/memory/` 整個目錄 |
| `.claude/settings.json`、各條 symlink | 逐字對話紀錄、各工具本地狀態 |
| `AGENTS.md` 與 `CLAUDE.md` symlink | `hook-probe.log`（測試產物） |

## 記憶

`.agents/memory/` 三個 agent 共用，**整個目錄不入庫**，clone 後由腳本建立:

```bash
scripts/setup-memory-link.sh            # 接上 ~/.claude/projects/<slug>/memory
scripts/setup-memory-link.sh --dry-run
```

## 驗證

```bash
scripts/verify-agents.sh all      # 或 claude / codex / agy
```

三項獨立判定:

- **註冊** —— 禁止任何工具呼叫的前提下，agent 列得出 `probe-marker`
  → 證明是原生載入，不是它自己 grep 出來的
- **使用** —— 吐得出只寫在 `SKILL.md` 內文的字串
- **hook** —— `hook-probe.log` 出現新行

> 只看「使用」會誤判:agent 可以用 `grep -rn` 搜到檔案再讀出來，看起來像通過。
