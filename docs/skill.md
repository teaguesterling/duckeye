# AI Agent Integration

`duckeye` includes a standard agent skill (`skills/duckeye/SKILL.md`) for AI coding agents and harnesses, including **Antigravity (AGY)**, **Claude Code**, and **OpenCode**.

## Why Agents Use DuckEye

AI models typically consume excessive context tokens when dumping full files into chat. `duckeye` gives agents progressive tools to inspect documents efficiently:

1. **Outline First**: `duckeye -t large_doc.md` gives the model the full document outline in ~20 tokens.
2. **Selective Reading**: `duckeye -S "Authentication" large_doc.md` extracts only the relevant chapter.
3. **Keyword Focusing**: `duckeye -s "deprecated" CHANGELOG.md` retrieves only the affected paragraphs.
4. **Token-Saving Conversions**: `duckeye -S "Usage" -o text manual.pdf` converts formatted PDF sections to plain text without ANSI escape sequences.
5. **Fast Data Profiling**: `duckeye -Z large_table.parquet` gives the agent instant statistics, null percentages, and distributions without full table dumps.

---

## Installing the Skill

Run `./install.sh` to automatically install the skill into detected agent directories:

```bash
./install.sh
```

Or copy manually:

```bash
# Antigravity / Gemini CLI
mkdir -p ~/.gemini/config/skills/duckeye
cp skills/duckeye/SKILL.md ~/.gemini/config/skills/duckeye/

# Claude Code
mkdir -p ~/.claude/skills/duckeye
cp skills/duckeye/SKILL.md ~/.claude/skills/duckeye/

# OpenCode
mkdir -p ~/.config/opencode/skills/duckeye
cp skills/duckeye/SKILL.md ~/.config/opencode/skills/duckeye/
```
