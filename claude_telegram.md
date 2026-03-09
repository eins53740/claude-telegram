# Claude Code × Telegram Remote Control

Control your laptop's Claude Code CLI from your phone via a Telegram bot.

## Architecture

```
Phone (Telegram App)
    ↓ send message
Telegram Bot API (cloud)
    ↓ long-polling
Local Python Script (your laptop)
    ↓ subprocess
Claude Code CLI (claude -p "prompt")
    ↓ stdout
Local Python Script
    ↓ send reply
Telegram Bot API → Phone
```

No servers to deploy. The Python script runs on your laptop and polls Telegram for messages.

---

## Setup Guide

### 1. Create the Telegram Bot

1. Open Telegram on your phone
2. Search for **@BotFather** and start a chat
3. Send `/newbot`
4. Choose a name (e.g., `My Claude Bot`)
5. Choose a username (must end in `bot`, e.g., `bd_claude_code_bot`)
6. BotFather replies with your **bot token** — copy it
7. Save the token in [[BD_only/telegram_bot_token.md]]

### 2. Get Your Chat ID

1. Search for **@userinfobot** on Telegram and start a chat
2. It replies with your **chat ID** (a number like `123456789`)
3. This is your `ALLOWED_CHAT_ID` — only this ID can use the bot

### 3. Install Dependencies

Open a terminal on your laptop:

```powershell
cd C:\BD_Obsidian\WORKING_FOLDER\claude-telegram
pip install -r requirements.txt
```

This installs `python-telegram-bot` (v20+, async).

### 4. Configure the Script

Edit `claude_telegram_bot.py` and replace the two placeholders:

```python
BOT_TOKEN = "your-actual-token-here"
ALLOWED_CHAT_ID = 123456789  # your actual chat ID
```

Optionally change `DEFAULT_CWD` to the directory you want Claude to work in.

### 5. Run the Bot

```powershell
python claude_telegram_bot.py
```

You should see:
```
Bot started. Listening for chat ID 123456789.
Send /ping from Telegram to verify.
```

### 6. Test It

From Telegram, send these to your bot:

| Message | Expected Response |
|---------|-------------------|
| `/ping` | 🏓 Pong! Bot is running. |
| `/id` | Your chat ID: 123456789 |
| `what is 2+2` | Claude's answer to the math question |
| `list files in current directory` | Directory listing from your laptop |

---

## Security

- **Chat ID filtering**: Only messages from `ALLOWED_CHAT_ID` are processed. All others are silently ignored.
- **Token storage**: Keep the bot token in `BD_only/` — this folder is gitignored and never exposed.
- **No inbound connections**: The script uses long-polling (outbound HTTPS only). No ports opened on your laptop.
- **5-minute timeout**: Commands that take longer than 300 seconds are killed.

> **Warning**: Anyone who gets your bot token can impersonate the bot. If compromised, revoke it via @BotFather → `/revoke`.

---

## Run in Background (Optional)

### Simple (no console window)

```powershell
pythonw claude_telegram_bot.py
```

### Persistent (survives reboots)

Use **Windows Task Scheduler**:

1. Open Task Scheduler → Create Basic Task
2. Trigger: "When I log on"
3. Action: Start a program
   - Program: `pythonw`
   - Arguments: `C:\BD_Obsidian\WORKING_FOLDER\claude-telegram\claude_telegram_bot.py`
4. Enable "Restart the task if it fails" in Settings

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `claude` not found | Ensure Claude Code CLI is on your PATH. Run `claude --version` in terminal. |
| Bot doesn't respond | Check the terminal for errors. Verify token and chat ID. |
| Network timeout | Corporate network may block `api.telegram.org`. Test: `curl https://api.telegram.org` |
| Long responses cut off | Responses are auto-chunked at 4000 chars. Very large outputs may need multiple messages. |
| Timeout on long tasks | Increase `TIMEOUT_SECONDS` in the script (default: 300s = 5 min). |

---

## Phase 2 Enhancements

| Feature | Implementation |
|---------|---------------|
| Session persistence | Add `--session-id` flag to CLI call; `/newsession` command |
| Working directory | `/cd C:\path` command to switch working directory |
| File attachments | Send output as `.txt` file when > 4096 chars |
| Cancel command | Track subprocess PID; `/cancel` to kill running command |
| Multiple projects | `/project vault` to switch between preset paths |
| Status check | `/status` to show if a command is currently running |

---

## Files

| File | Purpose |
|------|---------|
| `claude_telegram_bot.py` | Bot script (this folder) |
| `requirements.txt` | Python dependencies |
| [[BD_only/telegram_bot_token.md]] | Bot token (sensitive) |
| `claude_telegram.md` | This guide |
