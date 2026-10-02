<#
.SYNOPSIS
    Unified launcher for one Claude Code Telegram channel bot.

.DESCRIPTION
    Launches ONE bot in the FOREGROUND (visible in the current console/tab), with
    its own isolated plugin state so multiple bots can run side by side.

    Isolation (the key fix): the official telegram plugin keeps its token,
    allowlist (access.json) and single-instance lock (bot.pid) in ONE state dir.
    By default that is ~/.claude/channels/telegram, shared by every session, so
    concurrent bots SIGTERM each other's poller. We point TELEGRAM_STATE_DIR at a
    per-bot directory (~/.claude/channels/<name>) so each bot is independent.

    Token resolution: the plugin reads TELEGRAM_BOT_TOKEN from the real env first,
    then falls back to <state-dir>/.env (server.ts: "real env wins"). We export it
    from the profile's .env, so the per-bot state dir needs no token file.

.PARAMETER ProfileDir
    Folder holding .env (TELEGRAM_BOT_TOKEN=...) and optional SYSTEM_PROMPT.md.

.PARAMETER RepoRoot
    Working directory for the claude session (loads its CLAUDE.md / docs / .claude).

.PARAMETER Model
    Claude model id. Empty lets claude pick its default.

.PARAMETER StateName
    Name of the per-bot state dir under ~/.claude/channels. Defaults to the
    profile folder's leaf name. Keep it unique per bot.

.PARAMETER McpDebug
    Pass --debug to claude so the telegram plugin's stderr (polling status, 409
    conflicts, handler errors) is visible in the console. Default: on.

.PARAMETER SkipPermissions
    Passes --dangerously-skip-permissions. Only on trusted machines.

.NOTES
    Run unattended by Watch-Channel.ps1 (restart supervisor) inside a titled tab.
    Foreground + a real console keeps claude in interactive channel mode.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProfileDir,
    [Parameter(Mandatory = $true)][string]$RepoRoot,
    [string]$Model = '',
    [string]$StateName = '',
    [bool]$McpDebug = $true,
    [switch]$SkipPermissions
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $ProfileDir)) { throw "ProfileDir not found: $ProfileDir" }
if (-not (Test-Path $RepoRoot))   { throw "RepoRoot not found: $RepoRoot" }

if ([string]::IsNullOrWhiteSpace($StateName)) { $StateName = Split-Path $ProfileDir -Leaf }
$stateDir = Join-Path $HOME ".claude\channels\$StateName"
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
$env:TELEGRAM_STATE_DIR = $stateDir

$envFile = Join-Path $ProfileDir '.env'
$prompt  = Join-Path $ProfileDir 'SYSTEM_PROMPT.md'

if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { return }
        $eq = $line.IndexOf('=')
        if ($eq -lt 1) { return }
        $key = $line.Substring(0, $eq).Trim()
        $val = $line.Substring($eq + 1).Trim().Trim('"').Trim("'")
        Set-Item -Path "Env:$key" -Value $val
    }
}

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    throw "claude CLI not found on PATH. Install Claude Code first."
}
if (-not (Get-Command bun -ErrorAction SilentlyContinue)) {
    Write-Warning "bun not found on PATH. The telegram channel plugin needs Bun (https://bun.sh)."
}

$tokenLabel = if ([string]::IsNullOrWhiteSpace($env:TELEGRAM_BOT_TOKEN)) {
    '(none in env; plugin <state-dir>/.env will be used)'
} elseif ($env:TELEGRAM_BOT_TOKEN.Length -ge 6) {
    "...$($env:TELEGRAM_BOT_TOKEN.Substring($env:TELEGRAM_BOT_TOKEN.Length - 6))"
} else { '****' }

Write-Host "Launching Claude Telegram channel" -ForegroundColor Cyan
Write-Host "  bot/state : $StateName -> $stateDir" -ForegroundColor DarkGray
Write-Host "  profile   : $ProfileDir"  -ForegroundColor DarkGray
Write-Host "  repo      : $RepoRoot"    -ForegroundColor DarkGray
Write-Host "  model     : $(if ($Model) { $Model } else { '(claude default)' })" -ForegroundColor DarkGray
Write-Host "  prompt    : $(if (Test-Path $prompt) { $prompt } else { '(none)' })" -ForegroundColor DarkGray
Write-Host "  token     : $tokenLabel" -ForegroundColor DarkGray

Push-Location $RepoRoot
try {
    $cliArgs = @('--channels', 'plugin:telegram@claude-plugins-official')
    if ($Model)            { $cliArgs += @('--model', $Model) }
    if (Test-Path $prompt) { $cliArgs += @('--append-system-prompt', "@$prompt") }
    if ($McpDebug)         { $cliArgs += '--debug' }
    if ($SkipPermissions)  { $cliArgs += '--dangerously-skip-permissions' }

    # Foreground, attached to the current console (the titled tab) so the
    # channel session and the plugin's --debug stderr are visible live.
    # Watch-Channel.ps1 owns restart-on-exit; we just run and return the code.
    & claude @cliArgs
    $code = $LASTEXITCODE
    Write-Host "claude exited with code $code" -ForegroundColor DarkGray
    exit $code
}
finally {
    Pop-Location
}
