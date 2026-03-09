@echo off
REM ─── Claude Telegram Bot — Windows Startup Script ───
REM Place a shortcut to this file in: shell:startup
REM   (Win+R → shell:startup → paste shortcut)
REM
REM This runs the bot with a visible console window showing logs.
REM Close the window or press Ctrl+C to stop.

title Claude Telegram Bot
cd /d "C:\BD_Obsidian\WORKING_FOLDER\claude-telegram"

echo Bot starting at %date% %time%
echo Log file: %cd%\claude_telegram_bot.log
echo.

python claude_telegram_bot.py

if %ERRORLEVEL% neq 0 (
    echo.
    echo Bot crashed with error code %ERRORLEVEL% at %date% %time%
    echo Restarting in 10 seconds...
    timeout /t 10 /nobreak >nul
    goto :eof
)
