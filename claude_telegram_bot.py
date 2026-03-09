"""
Claude Code Telegram Bot
Remote control Claude Code CLI from your phone via Telegram.
"""

import logging
import os
import sys
import subprocess
from logging.handlers import RotatingFileHandler
from dotenv import load_dotenv
from telegram import Update
from telegram.ext import Application, MessageHandler, CommandHandler, filters

load_dotenv(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env"))

# ─── LOGGING ────────────────────────────────────────────────────
LOG_FORMAT = "%(asctime)s [%(levelname)s] %(name)s — %(message)s"
LOG_DIR = os.path.dirname(os.path.abspath(__file__))
LOG_FILE = os.path.join(LOG_DIR, "claude_telegram_bot.log")

root_logger = logging.getLogger()
root_logger.setLevel(logging.INFO)

# Console handler (stdout)
console_handler = logging.StreamHandler()
console_handler.setFormatter(logging.Formatter(LOG_FORMAT))
root_logger.addHandler(console_handler)

# Rotating file handler (20 MB max, keep 5 backups)
file_handler = RotatingFileHandler(
    LOG_FILE, maxBytes=20 * 1024 * 1024, backupCount=5, encoding="utf-8"
)
file_handler.setFormatter(logging.Formatter(LOG_FORMAT))
root_logger.addHandler(file_handler)

# Suppress noisy HTTP polling messages (getUpdates every few seconds)
for _noisy in ("httpx", "httpcore", "hpack",
               "telegram.ext.Updater", "telegram.ext._updater",
               "telegram.ext._application", "telegram.ext._httpxrequest"):
    logging.getLogger(_noisy).setLevel(logging.WARNING)

log = logging.getLogger(__name__)

# ─── CONFIGURATION (from .env) ───────────────────────────────────
BOT_TOKEN = os.environ.get("BOT_TOKEN")
ALLOWED_CHAT_ID = os.environ.get("ALLOWED_CHAT_ID")
DEFAULT_CWD = os.environ.get("DEFAULT_CWD", r"C:\BD_Obsidian")
TIMEOUT_SECONDS = int(os.environ.get("TIMEOUT_SECONDS", "300"))

if not BOT_TOKEN or not ALLOWED_CHAT_ID:
    sys.exit("ERROR: BOT_TOKEN and ALLOWED_CHAT_ID must be set in .env")

ALLOWED_CHAT_ID = int(ALLOWED_CHAT_ID)
# ─────────────────────────────────────────────────────────────────


def is_authorized(update: Update) -> bool:
    chat_id = update.effective_chat.id
    if chat_id != ALLOWED_CHAT_ID:
        user = update.effective_user
        log.warning("UNAUTHORIZED access from chat_id=%s user=%s (%s)",
                     chat_id, user.username, user.full_name)
        return False
    return True


async def handle_message(update: Update, context) -> None:
    """Forward any text message to Claude Code CLI and return the result."""
    if not is_authorized(update):
        return

    prompt = update.message.text
    user = update.effective_user
    log.info("MSG from %s (chat_id=%s): %s",
             user.username, update.effective_chat.id, prompt[:120])
    await update.message.reply_text("⏳ Running...")

    try:
        cmd = ["claude", "-p", prompt]
        log.info("EXEC %s  cwd=%s  timeout=%ss", cmd[:2], DEFAULT_CWD, TIMEOUT_SECONDS)
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=TIMEOUT_SECONDS,
            cwd=DEFAULT_CWD,
        )
        log.info("DONE rc=%s  stdout=%d chars  stderr=%d chars",
                 result.returncode, len(result.stdout), len(result.stderr))
        output = result.stdout or result.stderr or "No output"
    except subprocess.TimeoutExpired:
        output = f"⏰ Command timed out ({TIMEOUT_SECONDS // 60} min limit)"
        log.warning("TIMEOUT after %ss", TIMEOUT_SECONDS)
    except FileNotFoundError:
        output = "❌ 'claude' CLI not found on PATH. Is Claude Code installed?"
        log.error("claude CLI not found on PATH")
    except Exception as e:
        output = f"❌ Error: {e}"
        log.exception("Unexpected error running claude CLI")

    # Telegram 4096 char limit — send in 4000-char chunks
    for i in range(0, len(output), 4000):
        await update.message.reply_text(output[i : i + 4000])


async def cmd_ping(update: Update, context) -> None:
    """Health check."""
    if not is_authorized(update):
        return
    await update.message.reply_text("🏓 Pong! Bot is running.")


async def cmd_id(update: Update, context) -> None:
    """Show caller's chat ID (useful for initial setup)."""
    await update.message.reply_text(f"Your chat ID: {update.effective_chat.id}")


def main() -> None:
    app = Application.builder().token(BOT_TOKEN).build()

    app.add_handler(CommandHandler("ping", cmd_ping))
    app.add_handler(CommandHandler("id", cmd_id))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_message))

    print(f"Bot started. Listening for chat ID {ALLOWED_CHAT_ID}.")
    print("Send /ping from Telegram to verify.")
    app.run_polling()


if __name__ == "__main__":
    main()
