<#
.SYNOPSIS
    Supervisor for ONE Telegram channel bot. Run this inside a (titled) terminal tab.

.DESCRIPTION
    - Sets the tab/window title to the bot name so you can tell tabs apart.
    - Reads the bot's entry from channels.json.
    - Runs Start-Channel.ps1 in the foreground (visible session + plugin --debug stderr).
    - On any exit, logs the exit code and RESTARTS after a short backoff.
    - Writes ~/.claude/channels/<name>/status.json on every transition so the
      monitor / Channels.ps1 doctor always knows running | exited | restarting.
    - Appends lifecycle events to ~/.claude/channels/<name>/logs/supervisor-<date>.log

    Stop a bot by closing its tab or Ctrl+C twice (the loop catches one).

.PARAMETER Name
    Bot name as listed in channels.json (e.g. uns-ot-expert).

.PARAMETER ManifestPath
    Path to channels.json. Defaults to the one beside this script.

.PARAMETER MaxBackoffSeconds
    Cap for the restart backoff. Default 30.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$ManifestPath = (Join-Path $PSScriptRoot 'channels.json'),
    [int]$MaxBackoffSeconds = 30
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $ManifestPath)) { throw "Manifest not found: $ManifestPath" }
$manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
$bot = $manifest.bots | Where-Object { $_.name -eq $Name }
if (-not $bot) { throw "Bot '$Name' not found in $ManifestPath" }

$title = if ($bot.tabTitle) { $bot.tabTitle } else { "tg:$Name" }
$Host.UI.RawUI.WindowTitle = $title
# Windows Terminal: set the tab title via the OSC 9;9 / OSC 0 escape too.
$esc = [char]27
Write-Host "$esc]0;$title$([char]7)" -NoNewline

$stateDir = Join-Path $HOME ".claude\channels\$Name"
$logDir   = Join-Path $stateDir 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$statusFile = Join-Path $stateDir 'status.json'
$supLog     = Join-Path $logDir ("supervisor-{0:yyyyMMdd}.log" -f (Get-Date))

function Write-Status([string]$state, [int]$exitCode = -1) {
    $obj = [ordered]@{
        name      = $Name
        title     = $title
        state     = $state
        exitCode  = $exitCode
        pid       = $PID
        repoRoot  = $bot.repoRoot
        updatedAt = (Get-Date).ToString('o')
    }
    try { $obj | ConvertTo-Json | Set-Content -Path $statusFile -Encoding UTF8 } catch {}
}

function Write-SupLog([string]$msg) {
    $line = "{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $msg
    Write-Host $line -ForegroundColor DarkCyan
    try { Add-Content -Path $supLog -Value $line -Encoding UTF8 } catch {}
}

$starter = Join-Path $PSScriptRoot 'Start-Channel.ps1'
Write-SupLog "supervisor up for '$Name' (title '$title'); starter=$starter"

$attempt = 0
while ($true) {
    $attempt++
    Write-Status 'running'
    Write-SupLog "starting claude (attempt #$attempt)"
    $start = Get-Date
    try {
        & $starter -ProfileDir $bot.profileDir -RepoRoot $bot.repoRoot `
                   -Model $bot.model -StateName $Name
        $code = $LASTEXITCODE
    } catch {
        $code = 1
        Write-SupLog "starter threw: $($_.Exception.Message)"
    }
    $ranSeconds = [int]((Get-Date) - $start).TotalSeconds
    Write-Status 'exited' $code
    Write-SupLog "claude exited code=$code after ${ranSeconds}s"

    # If it ran a long time it was healthy; reset the backoff.
    if ($ranSeconds -ge 60) { $attempt = 1 }
    $backoff = [Math]::Min($MaxBackoffSeconds, [Math]::Pow(2, [Math]::Min($attempt, 5)))
    Write-Status 'restarting'
    Write-SupLog "restarting in ${backoff}s"
    Start-Sleep -Seconds $backoff
}
