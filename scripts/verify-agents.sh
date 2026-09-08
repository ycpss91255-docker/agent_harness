#!/usr/bin/env bash
# 驗證三個 agent 能否讀到共用的 skill 與 hook。
#
# 三項獨立判定:
#   1. 註冊  agent 在「禁止任何工具呼叫」的前提下，列得出 probe-marker
#            → 證明技能是被原生載入到 context，不是它自己翻檔案找到的
#   2. 使用  agent 吐得出只寫在 SKILL.md 內文的驗證字串
#   3. hook  hook-probe.log 出現新行
#
# 只看第 2 項會誤判:agent 可以用 grep 搜到檔案再讀出來，看起來像通過。
#
# 用法: scripts/verify-agents.sh [claude|codex|agy|all]
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
LOG="$ROOT/hook-probe.log"
MARKER='PROBE-MARKER-OK-7Q4X'
SKILL='probe-marker'
P_LIST='不要執行任何指令、不要讀取任何檔案。僅根據你現在已知的資訊，列出你目前可用的 skill 名稱（只要清單）。'
P_USE='請給我 PROBE MARKER'

verdict() { if [ "$1" = 1 ]; then echo PASS; else echo FAIL; fi; }

run_one() {
  local name="$1"; shift
  printf '\n===== %s =====\n' "$name"

  # 1. 註冊
  local reg out
  out="$("$@" "$P_LIST" </dev/null 2>&1)" || true
  reg=0; printf '%s' "$out" | grep -q "$SKILL" && reg=1
  printf -- '--- 註冊 : %s\n' "$(verdict $reg)"

  # 2. 使用 + 3. hook
  : > "$LOG"
  out="$("$@" "$P_USE" </dev/null 2>&1)" || true
  local use=0; printf '%s' "$out" | grep -q "$MARKER" && use=1
  printf -- '--- 使用 : %s\n' "$(verdict $use)"
  if [ "$use" = 1 ] && [ "$reg" = 0 ]; then
    echo '           ^ 注意:未註冊卻拿得到字串 = agent 自行搜尋檔案，不算共用機制生效'
  fi
  local hk=0; [ -s "$LOG" ] && hk=1
  printf -- '--- hook : %s\n' "$(verdict $hk)"
  [ "$hk" = 1 ] && sed 's/^/           /' "$LOG"
  return 0
}

target="${1:-all}"
[ "$target" = all ] || [ "$target" = claude ] && command -v claude >/dev/null \
  && run_one "Claude Code" claude -p
[ "$target" = all ] || [ "$target" = codex ] && command -v codex >/dev/null \
  && run_one "Codex" codex exec --skip-git-repo-check --sandbox read-only
# agy headless 光靠 cwd 不會觸發 workspace 客製化探索，必須 --add-dir
[ "$target" = all ] || [ "$target" = agy ] && command -v agy >/dev/null \
  && run_one "agy (Antigravity)" agy --add-dir "$ROOT" -p
exit 0
