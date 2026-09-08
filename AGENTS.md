# Agent 行為模擬場

這個 repo 用來並行比較三個 CLI agent 的行為:
**Claude Code**、**OpenAI Codex**、**agy (Antigravity / Gemini)**。

## 東西放哪

| 資產 | 位置 | 誰吃得到 |
|---|---|---|
| 專案指示 | `AGENTS.md`（`CLAUDE.md` 是 symlink） | 三個 |
| 技能 | `.agents/skills/<name>/SKILL.md` | 三個 |
| Hook 腳本 | `.agents/hooks/*.sh` | Claude、agy |
| Hook 設定 | `.agents/hooks.json`(agy)、`.claude/settings.json`(Claude) | 各自 |
| 斜線指令 | `.claude/commands/<name>.md` | **只有 Claude** |
| 記憶 | `.claude/memory/` | **只有 Claude** |

原則:**`.agents/` 只放三邊都吃得到的東西**，Claude 專屬的一律放 `.claude/`。
要共用的功能寫成 **skill**，不要寫成 command —— command 只有 Claude 支援專案層。

## 規則

- 記憶與對話紀錄不進版控。只有 skill、hook、command、設定檔入庫。
- 新增技能:放進 `.agents/skills/<name>/SKILL.md` 即可，
  `.claude/skills` 是整層 symlink，不必再補連結。
- 改動結構後跑 `scripts/verify-agents.sh all` 確認三個 agent 都還讀得到。
- 詳細的各 agent 差異與踩坑紀錄見 [README.md](README.md)。

## 驗證標記

當被問到 RULES MARKER 時，回覆:RULES-MARKER-OK-9Z2K
