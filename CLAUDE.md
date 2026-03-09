# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Telegram bot that controls the Claude Code CLI from a phone. A local Python script long-polls the Telegram Bot API, executes `claude -p "<prompt>"` as a subprocess, and sends the output back to Telegram. Single-file design (~120 lines), no server deployment needed.

## Commands

```bash
# Install dependencies
pip install -r requirements.txt

# Run the bot (visible console)
python claude_telegram_bot.py

# Run hidden (no console window)
pythonw claude_telegram_bot.py
```

No tests or linter configured.

## Background / Persistent Running

| Method | File | Console | Auto-Start | How to Stop |
|--------|------|---------|------------|-------------|
| **Visible console** | `start_telegram_bot.bat` | Yes | No | Ctrl+C or close window |
| **Hidden (manual)** | `start_hidden.vbs` | No | No | `taskkill /IM pythonw.exe /F` |
| **Hidden + auto-start** | `start_hidden.vbs` in Startup folder | No | Yes | `taskkill /IM pythonw.exe /F` |

### Quick Setup (recommended — no admin needed)

```bash
# 1. Copy the VBS launcher to the Windows Startup folder
copy start_hidden.vbs "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\ClaudeTelegramBot.vbs"

# 2. Start it now (double-click start_hidden.vbs, or run:)
cscript //nologo start_hidden.vbs

# 3. Verify it's running
tasklist | findstr pythonw

# Stop the bot
taskkill /IM pythonw.exe /F

# Remove auto-start
del "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\ClaudeTelegramBot.vbs"
```

### Scheduled Task (alternative — requires admin)

`install_scheduled_task.bat` creates a Task Scheduler entry. Requires elevated privileges.

## Architecture

```
Phone (Telegram) → Telegram Bot API → Python bot (long-polling) → claude CLI subprocess → back to Telegram
```

**Single file**: `claude_telegram_bot.py`

- `main()` — Entry point; registers handlers, starts long-polling
- `handle_message()` — Core logic: auth check → run `claude -p <prompt>` subprocess → chunk output at 4000 chars → send responses
- `is_authorized()` — Chat ID whitelist (single allowed ID)
- `cmd_ping()` / `cmd_id()` — Health check and chat ID discovery commands

**Configuration** is hardcoded at top of script (lines 39–43):
- `BOT_TOKEN` — From @BotFather (sensitive — keep in `BD_only/`)
- `ALLOWED_CHAT_ID` — Whitelisted Telegram chat ID
- `DEFAULT_CWD` — Working directory for Claude subprocess
- `TIMEOUT_SECONDS` — 5-minute kill timeout for commands

**Logging**: Dual output (console + rotating file `claude_telegram_bot.log`, 20MB × 5 backups).

## Key Constraints

- Telegram message limit is 4096 chars; bot chunks at 4000
- Bot token is embedded in source — never commit real tokens
- `python-telegram-bot` v20+ (async API with `Application` builder pattern)
- Windows-only launcher (`start_telegram_bot.bat`)

## Planned Phase 2 Features (not yet implemented)

Session persistence, `/cd` for directory switching, file attachments for large outputs, `/cancel` for running commands, project presets, `/status` command. See `claude_telegram.md` for details.
