# Claude Code Telegram Bot

Control your laptop's Claude Code CLI from your phone via Telegram.

Send a message from Telegram, the bot executes `claude -p "<your prompt>"` locally, and sends the output back. No servers, no open ports — just a Python script long-polling the Telegram API from your machine.

## Architecture

```
Phone (Telegram App)
    │ send message (HTTPS)
    ▼
Telegram Bot API (cloud)
    │ long-polling (outbound HTTPS only)
    ▼
Python bot script (your laptop)
    │ subprocess.run(["claude", "-p", prompt])
    ▼
Claude Code CLI
    │ stdout / stderr
    ▼
Python bot script
    │ send reply (HTTPS)
    ▼
Telegram Bot API → Phone
```

### Why long-polling instead of webhooks?

- **No server needed** — runs on your laptop, not a VPS
- **No open ports** — all traffic is outbound HTTPS (port 443)
- **Works behind NAT/firewalls/corporate proxies** — no inbound connections required
- **Zero infrastructure** — no domain, no SSL cert, no reverse proxy

### How the subprocess model works

Each Telegram message triggers a **blocking** `subprocess.run()` call to `claude -p`. This means:
- One command runs at a time (messages queue up)
- The bot sends "Running..." immediately, then waits for the CLI to finish
- Output is captured from stdout/stderr and chunked at 4000 chars (Telegram's limit is 4096)
- A 5-minute timeout kills hung commands (`TIMEOUT_SECONDS` in `.env`)

## Prerequisites

- **Python 3.10+**
- **Claude Code CLI** installed and on PATH (`claude --version` must work)
- **Telegram account** on your phone

## Setup

### 1. Create the Telegram Bot

1. Open Telegram, search for **@BotFather**, start a chat
2. Send `/newbot`
3. Choose a name (e.g., `My Claude Bot`) and a username (must end in `bot`)
4. BotFather replies with your **bot token** — save it securely

### 2. Get Your Chat ID

1. Search for **@userinfobot** on Telegram, start a chat
2. It replies with your **chat ID** (a number like `1389916364`)
3. This becomes your `ALLOWED_CHAT_ID` — only this ID can interact with the bot

> **Alternative**: Run the bot without `ALLOWED_CHAT_ID` set, send `/id` to it, and note the chat ID it returns.

### 3. Install and Configure

```bash
git clone https://github.com/eins53740/claude-telegram.git
cd claude-telegram
pip install -r requirements.txt
cp .env.example .env
# Edit .env with your actual values
```

`.env` file:
```env
BOT_TOKEN=your-bot-token-from-botfather
ALLOWED_CHAT_ID=your-chat-id-from-userinfobot
DEFAULT_CWD=C:\your\working\directory
TIMEOUT_SECONDS=300
```

| Variable | Required | Description |
|----------|----------|-------------|
| `BOT_TOKEN` | Yes | Bot API token from @BotFather |
| `ALLOWED_CHAT_ID` | Yes | Your Telegram chat ID (integer). Only this user can interact. |
| `DEFAULT_CWD` | No | Working directory for `claude` subprocess (default: `C:\BD_Obsidian`) |
| `TIMEOUT_SECONDS` | No | Max seconds per command before kill (default: `300`) |

### 4. Run

```bash
python claude_telegram_bot.py
```

Expected output:
```
Bot started. Listening for chat ID 1389916364.
Send /ping from Telegram to verify.
```

### 5. Test from Telegram

| Message | Expected Response |
|---------|-------------------|
| `/ping` | Pong! Bot is running. |
| `/id` | Your chat ID: 1389916364 |
| `what is 2+2` | Claude's answer |
| `list files in current directory` | Directory listing from your laptop |

## Bot Commands

| Command | Auth Required | Description |
|---------|--------------|-------------|
| `/ping` | Yes | Health check — confirms bot is alive |
| `/id` | No | Returns your chat ID (useful during initial setup) |
| Any text | Yes | Forwarded to `claude -p "<text>"` as a prompt |

## Running in Background

| Method | File | Console | Auto-Start | How to Stop |
|--------|------|---------|------------|-------------|
| **Visible console** | `start_telegram_bot.bat` | Yes | No | Ctrl+C or close window |
| **Hidden (manual)** | `start_hidden.vbs` | No | No | `taskkill /IM pythonw.exe /F` |
| **Hidden + auto-start** | `start_hidden.vbs` in Startup folder | No | Yes | `taskkill /IM pythonw.exe /F` |

### Quick Setup (recommended — no admin needed)

Copy the VBS launcher to the Windows Startup folder so the bot starts hidden on every logon:

```bash
# 1. Install auto-start
copy start_hidden.vbs "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\ClaudeTelegramBot.vbs"

# 2. Start it now (or double-click start_hidden.vbs)
cscript //nologo start_hidden.vbs

# 3. Verify it's running
tasklist | findstr pythonw

# Stop the bot
taskkill /IM pythonw.exe /F

# Remove auto-start
del "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\ClaudeTelegramBot.vbs"
```

### Scheduled Task (alternative — requires admin)

`install_scheduled_task.bat` creates a Windows Task Scheduler entry that runs at logon. Requires elevated privileges. Use the Startup folder method above if you don't have admin access.

## Logging

The bot logs to **two destinations simultaneously**:

| Destination | Format | Purpose |
|------------|--------|---------|
| Console (stdout) | Timestamped with level and logger name | Live debugging |
| `claude_telegram_bot.log` | Same format, rotating file | Persistent audit trail |

**Rotating file config**: 20 MB max per file, keeps 5 backups (`*.log.1` through `*.log.5`).

### What gets logged

| Event | Level | Example |
|-------|-------|---------|
| Incoming message | INFO | `MSG from username (chat_id=123): prompt text...` |
| Command execution | INFO | `EXEC ['claude', '-p'] cwd=C:\BD_Obsidian timeout=300s` |
| Command result | INFO | `DONE rc=0 stdout=1234 chars stderr=0 chars` |
| Unauthorized access | WARNING | `UNAUTHORIZED access from chat_id=999 user=hacker (John)` |
| Command timeout | WARNING | `TIMEOUT after 300s` |
| CLI not found | ERROR | `claude CLI not found on PATH` |
| Unexpected error | ERROR | Full stack trace |

### Suppressed loggers

The `python-telegram-bot` library polls Telegram every few seconds, generating noisy HTTP logs. These are suppressed at WARNING level:

`httpx`, `httpcore`, `hpack`, `telegram.ext.Updater`, `telegram.ext._updater`, `telegram.ext._application`, `telegram.ext._httpxrequest`

If you still see `HTTP Request: POST .../getUpdates` spam, identify the logger name from the log format (`%(name)s`) and add it to the suppression list on line 38.

## Security Model

| Layer | Mechanism |
|-------|-----------|
| **Authentication** | Chat ID whitelist — only `ALLOWED_CHAT_ID` can interact. Others are silently ignored and logged. |
| **Token security** | Bot token lives in `.env` (gitignored). Never committed to the repo. |
| **Network** | Long-polling = outbound HTTPS only. No listening ports, no inbound firewall rules needed. |
| **Process isolation** | Each `claude` call runs as a subprocess with a timeout. No persistent shell sessions. |
| **Audit trail** | Every access attempt (authorized or not) is logged with timestamp, username, and chat ID. |

### If your bot token is compromised

1. Open Telegram, message **@BotFather**
2. Send `/revoke` and select your bot
3. You'll get a new token — update your `.env`
4. Restart the bot

## Troubleshooting

### Bot doesn't start

| Symptom | Cause | Fix |
|---------|-------|-----|
| `ERROR: BOT_TOKEN and ALLOWED_CHAT_ID must be set in .env` | Missing or empty `.env` | Copy `.env.example` to `.env` and fill in your values |
| `ModuleNotFoundError: No module named 'telegram'` | Dependencies not installed | `pip install -r requirements.txt` |
| `ModuleNotFoundError: No module named 'dotenv'` | Missing python-dotenv | `pip install python-dotenv` |
| `ImportError` or version errors | Wrong python-telegram-bot version | Need v20+ (async API). `pip install --upgrade python-telegram-bot` |

### Bot starts but doesn't respond

| Symptom | Cause | Fix |
|---------|-------|-----|
| No output at all when messaging | Wrong chat ID in `.env` | Send `/id` to the bot — compare with `ALLOWED_CHAT_ID` |
| Console shows `UNAUTHORIZED access` | Someone else (or wrong account) is messaging | Verify the chat ID matches your Telegram account |
| Bot responds to `/ping` but not text | Handler order issue | Unlikely with current code — check for import errors in logs |
| "Running..." but never replies | `claude` command hanging | Check `TIMEOUT_SECONDS`, verify `claude -p "hello"` works in terminal |

### Claude CLI issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| `'claude' CLI not found on PATH` | CLI not installed or not on PATH | Install Claude Code CLI. Run `claude --version` in the same terminal. |
| `No output` response | CLI returned empty stdout and stderr | Run the same prompt manually: `claude -p "your prompt"` in terminal |
| Timeout on every command | Network or API issues | Check Claude's API status. Try `claude -p "say hi"` manually. |
| Output is `stderr` content | CLI error (non-zero exit code) | Check logs for `rc=` value. Run the prompt manually to reproduce. |

### Network issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Connection error` or `TimeoutError` on startup | `api.telegram.org` blocked | Test: `curl https://api.telegram.org`. Corporate networks may block it. Use a VPN or personal hotspot. |
| Bot works on home WiFi but not office | Corporate proxy/firewall | Telegram API uses HTTPS on port 443. Check if your proxy allows it. Set `HTTPS_PROXY` env var if needed. |
| Intermittent disconnects | Unstable connection | The library auto-reconnects. Check logs for reconnection patterns. |

### Log-related issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| `HTTP Request: POST .../getUpdates` spam | Logger not suppressed | Find the logger name in the log output and add it to the suppression list (line 38 in the script) |
| Log file not created | Permission issue or wrong path | Check `LOG_DIR` points to a writable directory. Default is the script's own directory. |
| Log file growing too large | Rotation not working | Should auto-rotate at 20 MB. Check disk space. Logs older than 5 rotations are deleted. |

### Windows-specific issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| `.bat` script flashes and disappears | Python error on startup | Run `python claude_telegram_bot.py` directly in a terminal to see the error |
| Startup shortcut doesn't work after moving the project | Stale path in shortcut | Re-create the shortcut pointing to the new `startup_telegram_bot.bat` location |
| `pythonw` not found | Python not on PATH | Use full path: `C:\Python3xx\pythonw.exe` or add Python to PATH |
| Bot doesn't start on login | Task Scheduler or shortcut misconfigured | Check the shortcut target path. Verify "Start in" directory is correct. |

## Design Decisions

### Why `subprocess.run` instead of the Claude API directly?

- **Reuses CLI authentication** — no separate API key management
- **Same behavior as terminal** — what you'd type on your laptop is what runs
- **CLI handles model selection, context, tools** — the bot is just a thin relay
- **Simpler code** — no API client, no token refresh, no streaming logic

### Why single-file architecture?

- ~130 lines total — easy to read, debug, and modify
- No framework overhead, no project scaffolding
- All configuration in `.env`, all logic in one place
- For a personal tool, simplicity beats structure

### Why `python-telegram-bot` v20+?

- Official, well-maintained library
- Async API (uses `asyncio`) — efficient for I/O-bound polling
- Built-in handler routing (commands vs. text messages)
- Handles reconnection and error recovery automatically

### Why chat ID auth instead of a password/command?

- Chat IDs are immutable and tied to the Telegram account
- No risk of password interception in message history
- No "login" step needed — just message the bot
- Unauthorized attempts are silently dropped and logged

## Phase 2 Roadmap

Planned but not yet implemented:

| Feature | Implementation |
|---------|---------------|
| Session persistence | Add `--session-id` flag to CLI call; `/newsession` command to reset |
| Working directory | `/cd C:\path` command to switch working directory at runtime |
| File attachments | Send output as `.txt` file when > 4096 chars instead of chunking |
| Cancel command | Track subprocess PID; `/cancel` to kill a running command |
| Multiple projects | `/project vault` to switch between preset paths |
| Status check | `/status` to show if a command is currently running |

## Project Structure

```
claude-telegram/
├── .env                    # Your secrets (gitignored)
├── .env.example            # Template for .env
├── .gitignore
├── CLAUDE.md               # Claude Code context file
├── README.md               # This file
├── claude_telegram_bot.py  # Bot script (~130 lines)
├── requirements.txt        # pip dependencies
├── start_telegram_bot.bat       # Manual launcher (visible console)
├── start_hidden.vbs             # Hidden launcher (no console window)
├── install_scheduled_task.bat   # Task Scheduler installer/uninstaller
└── startup_telegram_bot.bat     # Windows Startup launcher (visible)
```

## License

Personal project. Use at your own risk.
