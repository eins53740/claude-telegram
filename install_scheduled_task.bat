@echo off
REM ─── Claude Telegram Bot — Task Scheduler Installer ───
REM Creates a Windows Scheduled Task that:
REM   - Starts the bot at user logon (hidden, no console window)
REM   - Auto-restarts on failure (every 60 seconds, up to 3 retries)
REM   - Runs under the current user account
REM
REM Usage:
REM   install_scheduled_task.bat          — install the task
REM   install_scheduled_task.bat remove   — remove the task

set TASK_NAME=ClaudeTelegramBot
set BOT_DIR=%~dp0
set BOT_SCRIPT=%BOT_DIR%claude_telegram_bot.py

if /i "%~1"=="remove" goto :remove

echo ============================================
echo   Installing Scheduled Task: %TASK_NAME%
echo ============================================
echo.

REM Find pythonw.exe from the same Python that's on PATH
for /f "delims=" %%i in ('python -c "import sys, os; print(os.path.join(os.path.dirname(sys.executable), 'pythonw.exe'))"') do set PYTHONW=%%i

if not exist "%PYTHONW%" (
    echo ERROR: pythonw.exe not found at %PYTHONW%
    echo Make sure Python is installed and on PATH.
    pause
    exit /b 1
)

echo Python:    %PYTHONW%
echo Script:    %BOT_SCRIPT%
echo Directory: %BOT_DIR%
echo.

REM Remove existing task if present (ignore errors)
schtasks /delete /tn "%TASK_NAME%" /f >nul 2>&1

REM Create the scheduled task
schtasks /create ^
    /tn "%TASK_NAME%" ^
    /tr "\"%PYTHONW%\" \"%BOT_SCRIPT%\"" ^
    /sc onlogon ^
    /rl limited ^
    /f

if %ERRORLEVEL% neq 0 (
    echo.
    echo ERROR: Failed to create scheduled task.
    echo Try running this script as Administrator.
    pause
    exit /b 1
)

echo.
echo Task created successfully.
echo.
echo The bot will start automatically at next logon.
echo To start it now without rebooting:
echo   schtasks /run /tn "%TASK_NAME%"
echo.
echo To check status:
echo   schtasks /query /tn "%TASK_NAME%"
echo.
pause
exit /b 0

:remove
echo Removing scheduled task: %TASK_NAME%
schtasks /delete /tn "%TASK_NAME%" /f
if %ERRORLEVEL% equ 0 (
    echo Task removed successfully.
) else (
    echo Task not found or could not be removed.
)
pause
exit /b 0
