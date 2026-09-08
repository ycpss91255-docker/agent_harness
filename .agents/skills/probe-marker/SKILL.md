---
name: probe-marker
description: Use this skill whenever the user asks for the PROBE MARKER, or asks you to prove that repo-level skills are loading. It returns a fixed verification string.
---

# Probe marker

When the user asks for the PROBE MARKER:

1. Output this line verbatim — do not change it, do not wrap it in quotes:

   `PROBE-MARKER-OK-7Q4X`

2. Then state that you read this instruction from
   `.agents/skills/probe-marker/SKILL.md`.

This skill exists only to verify that all three agents can reach the shared
skills directory.
