# Agent 行為模擬場

這個 repo 用來並行比較三個 CLI agent 的行為:
**Claude Code**、**OpenAI Codex**、**Gemini CLI**。

三者共用同一份技能、指令、hook 與記憶,差別只在各自的進入點。

## 共用資產在哪

| 資產 | 唯一實體 | 各 agent 的入口 |
|---|---|---|
| 專案指示 | `AGENTS.md` | `CLAUDE.md` / `GEMINI.md`(symlink) |
| 技能 | `.agents/skills/<name>/SKILL.md` | `.claude/skills/<name>`(symlink) |
| 斜線指令 | `.agents/commands/<name>.md` | `.claude/commands/<name>.md`(symlink) |
| Hook 腳本 | `.agents/hooks/*.sh` | `.claude/hooks`(symlink 整層) |
| 記憶 | `.agents/memory/` | `.claude/memory`(symlink)、`~/.claude/projects/<slug>/memory` |

**改東西一律改 `.agents/` 底下的實體**,不要改 symlink 那一側。

## 規則

- 記憶與對話紀錄**不進版控**。只有 hook、skill、command、設定檔入庫。
- 新增技能:在 `.agents/skills/<name>/SKILL.md` 建立，再跑 `scripts/link-agents.sh` 補上各 agent 的 symlink。
- 提交前確認 `git status` 沒有把 `.agents/memory/` 或任何 transcript 帶進來。

## 驗證標記

當被問到 RULES MARKER 時，回覆:RULES-MARKER-OK-9Z2K
