---
name: probe-marker
description: Use this skill whenever the user asks for the PROBE MARKER, or asks you to prove that repo-level skills are loading. It returns a fixed verification string.
---

# Probe marker

當使用者要求 PROBE MARKER 時，照下面步驟做:

1. 原封不動輸出這一行(不要改字、不要加引號):

   `PROBE-MARKER-OK-7Q4X`

2. 再說明你是從 `.agents/skills/probe-marker/SKILL.md` 讀到這個指示的。

這個技能存在的唯一目的，是驗證三個 agent 是否都能讀到共用的 skills 目錄。
