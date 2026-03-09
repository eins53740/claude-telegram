' ─── Claude Telegram Bot — Hidden Launcher ───
' Runs the bot with no console window using pythonw.
' The bot still logs to claude_telegram_bot.log.
'
' Usage: double-click this file, or place a shortcut in shell:startup
'   (Win+R → shell:startup → create shortcut to this file)
'
' To stop: Task Manager → Details → pythonw.exe → End Task
'   Or use: taskkill /IM pythonw.exe /F

Set WshShell = CreateObject("WScript.Shell")
strDir = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
WshShell.CurrentDirectory = strDir
WshShell.Run "pythonw """ & strDir & "\claude_telegram_bot.py""", 0, False
