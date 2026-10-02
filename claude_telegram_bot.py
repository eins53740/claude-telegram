"""
Claude Code Telegram Bot
Remote control Claude Code CLI from your phone via Telegram.
"""

import logging
import os
import sys
import subprocess
import msvcrt
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



def _default_cwd() -> str:
    """Where a chat command runs when .env does not say.

    The vault is C:\\BD_Obsidian on the laptop and D:\\BD_Obsidian on vmhost1. The fallback
    here named the C: spelling, and this bot's scheduled task (ClaudeTelegramBot) runs on
    VMHOST1 - where that path does not exist. Probe both and fall back to the user profile,
    which always does, rather than handing the subprocess a directory that isn't there.
    """
    for root in (r"D:\BD_Obsidian", r"C:\BD_Obsidian"):
        if os.path.isdir(root):
            return root
    return os.path.expanduser("~")


DEFAULT_CWD = os.environ.get("DEFAULT_CWD") or _default_cwd()
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
        # Remove CLAUDECODE env var to avoid nested-session detection
        env = {k: v for k, v in os.environ.items() if k != "CLAUDECODE"}
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            encoding="utf-8",
            timeout=TIMEOUT_SECONDS,
            cwd=DEFAULT_CWD,
            env=env,
            creationflags=subprocess.CREATE_NO_WINDOW,
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


def acquire_lock():
    """Ensure only one bot instance runs at a time using a lock file."""
    lock_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".bot.lock")
    lock_file = open(lock_path, "w")
    try:
        msvcrt.locking(lock_file.fileno(), msvcrt.LK_NBLCK, 1)
    except OSError:
        sys.exit("ERROR: Another bot instance is already running. Exiting.")
    return lock_file  # must keep reference alive to hold the lock


def main() -> None:
    lock = acquire_lock()  # noqa: F841 — reference kept to hold file lock

    app = Application.builder().token(BOT_TOKEN).build()

    app.add_handler(CommandHandler("ping", cmd_ping))
    app.add_handler(CommandHandler("id", cmd_id))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_message))

    print(f"Bot started. Listening for chat ID {ALLOWED_CHAT_ID}.")
    print("Send /ping from Telegram to verify.")
    app.run_polling()


if __name__ == "__main__":
    main()
