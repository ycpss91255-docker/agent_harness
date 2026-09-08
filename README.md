# agent — 三個 CLI agent 的共用骨架

同一份技能／指令／hook／記憶，讓 **Claude Code**、**OpenAI Codex**、
**Gemini CLI** 三邊都吃得到，用來並行比較它們的行為差異。

## 結構

```
agent/
├── AGENTS.md                    專案指示（單一事實來源）
├── CLAUDE.md  -> AGENTS.md
├── GEMINI.md  -> AGENTS.md
│
├── .agents/                     唯一實體，所有內容都寫在這裡
│   ├── skills/
│   ├── commands/
│   ├── hooks/
│   └── memory/                  完全不進版控（clone 後由腳本建立）
│
├── .claude/  skills|commands|hooks|memory -> ../.agents/*
│   └── settings.json
├── .codex/   skills|commands|hooks|memory -> ../.agents/*
├── .gemini/  skills|commands|hooks|memory -> ../.agents/*
│   └── settings.json
│
├── scripts/setup-memory-link.sh
└── .gitignore
```

**整層 symlink**，不是逐項連結 —— 新增一個技能只要放進 `.agents/skills/`，
三個 agent 立刻都看得到，不必再補連結或跑同步腳本。

## 進版控的 / 不進版控的

| 進 | 不進 |
|---|---|
| `.agents/` 底下的 skills、commands、hooks | `.agents/memory/` 整個目錄（含內容，零檔案入庫） |
| 各 agent 的 `settings.json`、symlink 本身 | 逐字對話紀錄（`.claude/projects/` 等） |
| `AGENTS.md` 與兩條 symlink | 各工具的本地狀態、`settings.local.json` |

## 記憶怎麼接

`.agents/memory/` 是三個 agent 共用的實體，**整個目錄都不入庫**，
所以 clone 下來不存在，由腳本建立。Claude Code 預期記憶放在
`~/.claude/projects/<路徑 slug>/memory`，用腳本接過去:

```bash
scripts/setup-memory-link.sh            # 目前目錄
scripts/setup-memory-link.sh --dry-run  # 先看會做什麼
```

腳本是冪等的:已經接好就跳過；目標不對會替換；本地有新內容會拒絕並要你先
合併，`--force` 則會先備份再換。

## 各 agent 的接法：可信度不同

| 工具 | 進入點 | 把握度 |
|---|---|---|
| Claude Code | `CLAUDE.md`、`.claude/settings.json`、`.claude/skills\|commands\|hooks` | 高 |
| Gemini CLI | `GEMINI.md`、`.gemini/settings.json` | 中 |
| OpenAI Codex | `AGENTS.md` | `AGENTS.md` 高；專案層 `.codex/` 的實際讀取路徑**未驗證** |

`.codex/` 底下那幾條 symlink 是照對稱性擺的，Codex 是否真的會讀取尚待實測。
確定讀不到的話直接刪掉那層即可，不影響其他兩個。
