@echo off
title Claude Telegram Bot
cd /d "%~dp0"

echo ============================================
echo   Claude Telegram Bot
echo ============================================
echo.
echo  Log file: %~dp0claude_telegram_bot.log
echo  Press Ctrl+C to stop.
echo.

python claude_telegram_bot.py

if %ERRORLEVEL% neq 0 (
    echo.
    echo Bot exited with error code %ERRORLEVEL%
    pause
)
