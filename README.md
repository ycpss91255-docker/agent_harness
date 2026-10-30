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
├── .codex/                  Codex 專用
│   └── hooks.json              Codex 的 hook 設定（Codex 讀 project hooks 的
│                                兩個檔案之一，另一個是 .codex/config.toml，
│                                這裡沒用到）
│
└── script/
    ├── ci/ci.sh              CI 檢查（每個 PR 都跑）
    ├── gh-issue.sh -> ../dist/agents/scripts/gh-issue.sh
    ├── setup-memory-link.sh
    └── verify-agents.sh
```

**沒有 `.gemini/`** —— 實測拿掉後功能完全不變。

**`.codex/` —— 當初那個決定在當下是對的，過期的是它的前提。**
這個 repo 一直沒有 `.codex/` 目錄，理由是實測過拿掉之後什麼都沒變。
那次實測沒錯，就它涵蓋的範圍來說到現在也還成立:沒有 `.codex/`，skills、prompts、
rules 照樣從 `.agents/` 與 `AGENTS.md` 載入。變的是底下那一層 —— `.codex/`
成了 Codex 讀 **project hooks** 的目錄。2026-09-09 以 codex-cli 0.153.2 重測:
接在 `<repo>/.codex/hooks.json` 裡的 hook 會觸發。所以目錄回來了，裡面就一個
檔案，而這件事該記成「重測，地基動了」，不是「當初做錯了」。

畫界線的是目錄，不是檔名。`hooks/list` 對宣告在 `<repo>/.codex/hooks.json`
**或** `<repo>/.codex/config.toml` 的 `[[hooks.*]]` 區塊裡的 hook，兩邊都回報
`source: "project"`，每一筆各自把自己的檔案寫在 `sourcePath`（2026-09-09
實測，兩層都測，同一個 repo）。實測*讀不到*的是 `.agents/`:同一份檔案放到
`<repo>/.agents/hooks.json`，一筆都不會出現。這個 repo 用 `hooks.json` 是因為它
比較小、也不必寫 TOML；那是偏好，不是唯一行得通的路。

## 誰吃得到什麼（全部實測）

| 資產 | Claude Code | Codex | agy |
|---|---|---|---|
| **skills** | 讀 `.claude/skills/`，**不讀 `.agents/`** → 靠 symlink | 原生讀 `.agents/skills/` | 原生讀 `.agents/skills/`（headless 需 `--add-dir`） |
| **rules** | 只讀 `CLAUDE.md` → symlink 到 `AGENTS.md` | 讀 `AGENTS.md` | 讀 `AGENTS.md` |
| **hooks** | `.claude/settings.json` | `.codex/hooks.json` 或 `.codex/config.toml` —— **不會是 `.agents/`**，而且後面還卡著兩道信任關卡 | `.agents/hooks.json` |
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
- **有 project hooks，而且是從 `.codex/` 讀的**（codex-cli 0.153.2，
  2026-09-09 實測）—— `<repo>/.codex/hooks.json`，也就是這個 repo 現在放的
  那一份；同樣算數的還有 `<repo>/.codex/config.toml` 裡的 `[[hooks.*]]`
  區塊。`hooks/list` 兩邊都回 `source: "project"`。同一份檔案放到 `.agents/`
  底下就不會被撿起來。設定格式與 payload 跟 Claude Code 一樣:`PreToolUse`
  用 `matcher` + `hooks`、`tool_name` 是 `"Bash"`、`tool_input.command`，回覆用
  `hookSpecificOutput.permissionDecision`。有五件事不一樣，每一件都足以讓你接好的
  hook 從來不跑:

  - 命令是**丟給 shell 跑**的，但工作目錄是 **session 當下的目錄**，
    不是 repo root，而且 Codex 自己不設任何指向專案目錄的變數。直接寫 `./…`
    在 root 下可以動，往下一層就壞；`"$(git rev-parse --show-toplevel)/…"`
    則在任何深度都能動。
  - **專案必須先被信任** —— 在 `~/.codex/config.toml` 裡
    （`[projects."<path>"] trust_level = "trusted"`），而且那一筆要**點名 repo root
    本身**:信任不會往下繼承，只寫了父目錄的話，巢狀在它底下的 repo 依然是
    untrusted。用 `-c` 覆寫也沒用 —— 信任是從檔案讀的，不是從合併後的 config。
  - **每一個 hook 都要逐一審過。** 剛 clone 下來的 hook 是 `untrusted`，不會跑；
    審核是走 TUI 的流程，而且 hook 設定一改，記下來的 hash 就跟著變。
    非互動的執行要加 `--dangerously-bypass-hook-trust`。
  - 在 `codex exec` 底下，**兩道關卡都是無聲失敗**:沒有 hook 那一行、沒有警告、
    什麼都不跑。信任那一道關卡在別的地方*並不*安靜 —— app-server 與 TUI 會印一行
    `ERROR` 點名那個未被信任的 `.codex` 目錄，並且不從裡面載入任何 project hook。
    也就是說，把 `.codex/` 加進一個不是受信任專案的 repo，在每一個入口都看得出來，
    唯獨這個 repo 自己的檢查用的那一個看不出來。**這個 repo 正是這種 repo**:
    `~/.codex/config.toml` 底下沒有任何一筆點名它的 root，所以它現在放的這份
    `.codex/hooks.json` 在這裡是不會動的，直到有人把那一筆加上去。
  - `handlerType: command` 是唯一**被實測證明會動**的 handler，但這跟「Codex 只收
    這一種」不是同一回事。`prompt` 與 `agent` 會被直接拒絕（「prompt hooks are
    not supported yet」）。`mcp_tool` 則是解析得過、列得出來是啟用中的 project
    hook、也真的有被派送出去 —— 這裡會失敗只是因為它指名的那個 MCP server
    不存在，所以它既沒被證明會動，也沒被拒絕。附帶一個陷阱:設定的 parser 只吃
    `command|mcp_tool|prompt|agent`，而 `mcpTool` —— `hooks/list` 自己印回來的
    就是這個拼法 —— 會被當成未知的變體拒掉，連帶讓那個檔案裡的**每一個**
    hook 都不見；這件事只會在 `hooks/list` 以警告的形式報出來，`codex exec`
    底下則完全不報。

  2026-09-09 實測:Codex 真的會**照著 deny 動作**。兩道關卡都清掉之後跑
  `codex exec`，印出 `hook: PreToolUse Blocked` 與 `Command blocked by PreToolUse
  hook: …`，從 repo root 跑跟從子目錄跑都一樣，而且排在 `PATH` 最前面的 `gh`
  假替身一次都沒被叫到 —— 命令根本沒有執行。這段在那次執行之前寫的是
  「未經驗證」；差別在於這是實際跑出來的，不是從 binary 裡讀出來的。

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

> **Codex 這一項是反過來判，不是跳過 —— 而且這個反判是新的。** 它跟著 Codex 的
> hook 接線一起進來，同一次改動，不是從以前沿用下來的。在那之前 Codex 跑的是和
> 另外兩個 agent 一模一樣的 `[ -s "$LOG" ]` 斷言 —— 一個完全沒接 probe hook 的
> agent，就是這樣靠別的 session 寫下的行拿到 PASS 的。現在它存在的理由很窄:
> **這個 repo 沒有替 Codex 接 probe hook** —— `.codex/hooks.json` 裡沒有列
> `test_probe.sh` —— 所以 probe 寫出來的任何一行都算不到 Codex 頭上，而
> 「**沒有**任何一行帶著這次執行的 nonce」是一個真的可能失敗的斷言。這是一個比
> 「Codex 根本沒有 hook 機制」小得多的說法 —— 後者正是同一次改動用實測推翻的
> （見上面 Codex 一節）。輸出上也標成 `inverted`，免得有人把它讀成「Codex 跑了
> hook」。它幾乎不花成本，也還抓得到兩件事:有人背著我們替 Codex 接上 probe
> hook，或 nonce 從 Codex process 漏進別的 agent 的 hook。

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
