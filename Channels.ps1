<#
.SYNOPSIS
    Manage and monitor the Claude Code Telegram bot fleet.

.DESCRIPTION
    One entry point for day-to-day operation of the bots in channels.json:
    health, logs, start/stop/restart, allowlist edits, and an unattended monitor
    that toasts you when a bot is down or erroring.

    OpenClaw is a SEPARATE runtime; it is shown read-only in 'doctor' for
    awareness but never started/stopped here.

.PARAMETER Action
    doctor | status   Health sweep of every bot (identity, polling, pid, state).
    logs              Tail a bot's supervisor log (-Mcp for plugin stderr jsonl).
    start-all         Open a Windows Terminal window, one titled tab per bot.
    start             Open one titled tab for -Name.
    stop | stop-all   Stop a bot (its supervisor + claude + bun + bot.pid).
    restart           stop then start -Name.
    monitor           One-shot health sweep -> fleet-status.json (+toast on problems).
    ids               Show each bot's allowlist and any pending pairings.
    allow             Add a numeric Telegram user id to -Name's allowlist (approve a device).
    policy            Set -Name's dmPolicy to -Value (pairing|allowlist|disabled).

.PARAMETER Name      Bot name from channels.json.
.PARAMETER Value     Argument for 'allow' (user id) or 'policy' (policy name).
.PARAMETER Tail      logs: number of trailing lines (default 40).
.PARAMETER Follow    logs: keep tailing.
.PARAMETER Mcp       logs: read the claude telegram-plugin stderr jsonl instead of supervisor log.

.EXAMPLE
  .\Channels.ps1 doctor
  .\Channels.ps1 logs -Name uns-ot-expert -Follow
  .\Channels.ps1 allow -Name uns-ot-expert -Value 1389916364
  .\Channels.ps1 start-all
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('doctor','status','logs','start-all','start','stop','stop-all','restart','monitor','ids','allow','policy')]
    [string]$Action,
    [string]$Name,
    [string]$Value,
    [int]$Tail = 40,
    [switch]$Follow,
    [switch]$Mcp
)

$ErrorActionPreference = 'Stop'
$ScriptDir    = $PSScriptRoot
$ManifestPath = Join-Path $ScriptDir 'channels.json'
$StateRoot    = Join-Path $HOME '.claude\channels'
$manifest     = Get-Content $ManifestPath -Raw | ConvertFrom-Json
$bots         = $manifest.bots

function Get-Bot([string]$n) {
    $b = $bots | Where-Object { $_.name -eq $n }
    if (-not $b) { throw "Bot '$n' not in channels.json. Known: $($bots.name -join ', ')" }
    $b
}

function Get-Token([object]$bot) {
    $envFile = Join-Path $bot.profileDir '.env'
    if (-not (Test-Path $envFile)) { return $null }
    foreach ($line in Get-Content $envFile) {
        if ($line -match '^\s*TELEGRAM_BOT_TOKEN\s*=\s*(.+?)\s*$') {
            return $Matches[1].Trim().Trim('"').Trim("'")
        }
    }
    return $null
}

function Invoke-Tg([string]$token, [string]$method) {
    if (-not $token) { return $null }
    try {
        return Invoke-RestMethod -Method Get -TimeoutSec 10 -Uri "https://api.telegram.org/bot$token/$method"
    } catch { return $null }
}

function Test-PidAlive([int]$processId) {
    if ($processId -le 0) { return $false }
    return [bool](Get-Process -Id $processId -ErrorAction SilentlyContinue)
}

function Test-SupervisorRunning([string]$n) {
    # Is a Watch-Channel.ps1 supervisor process alive for this bot? If so, it
    # owns restart and auto-heal must NOT spawn a second one (would 409).
    return [bool](Get-CimInstance Win32_Process -Filter "Name='pwsh.exe' OR Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match "Watch-Channel\.ps1.*-Name\s+'?$([regex]::Escape($n))\b" })
}

function Get-BotHealth([object]$bot) {
    $stateDir = Join-Path $StateRoot $bot.name
    $token    = Get-Token $bot
    $me   = Invoke-Tg $token 'getMe'
    $hook = Invoke-Tg $token 'getWebhookInfo'

    $pidFile = Join-Path $stateDir 'bot.pid'
    $pollerPid = if (Test-Path $pidFile) { [int]((Get-Content $pidFile -Raw).Trim()) } else { 0 }
    $pollerAlive = Test-PidAlive $pollerPid

    $statusFile = Join-Path $stateDir 'status.json'
    $supState = if (Test-Path $statusFile) { (Get-Content $statusFile -Raw | ConvertFrom-Json).state } else { 'unknown' }

    $pending = if ($hook) { [int]$hook.result.pending_update_count } else { $null }
    $lastErr = if ($hook -and $hook.result.last_error_message) { $hook.result.last_error_message } else { '' }
    $username = if ($me -and $me.ok) { $me.result.username } else { $null }

    # Verdict
    $level = 'OK'; $note = ''
    if (-not $token)            { $level = 'STOPPED'; $note = 'no token in .env' }
    elseif (-not $me -or -not $me.ok) { $level = 'STOPPED'; $note = 'token invalid / no API' }
    elseif (-not $pollerAlive)  { $level = 'STOPPED'; $note = 'no live poller (bot.pid dead)' }
    elseif ($lastErr)           { $level = 'WARN';    $note = "tg last_error: $lastErr" }
    elseif ($pending -gt 5)     { $level = 'WARN';    $note = "$pending updates not consumed" }
    else                        { $level = 'OK';      $note = "polling @$username" }

    [pscustomobject]@{
        Name = $bot.name; Title = $bot.tabTitle; Username = $username
        Level = $level; Poller = $(if($pollerAlive){"pid $pollerPid"}else{'dead'})
        Pending = $pending; Supervisor = $supState; Note = $note
    }
}

function Get-OpenClawHealth() {
    $cfg = "$HOME\.openclaw\openclaw.json"
    if (-not (Test-Path $cfg)) { return $null }
    $tok = $null
    foreach ($line in Get-Content $cfg) {
        if ($line -match '"botToken"\s*:\s*"([^"]+)"') { $tok = $Matches[1]; break }
    }
    $me   = Invoke-Tg $tok 'getMe'
    $hook = Invoke-Tg $tok 'getWebhookInfo'
    $pending = if ($hook) { [int]$hook.result.pending_update_count } else { $null }
    $username = if ($me -and $me.ok) { $me.result.username } else { '?' }
    $level = if (-not $me -or -not $me.ok) { 'WARN' } elseif ($pending -gt 5) { 'WARN' } else { 'OK' }
    [pscustomobject]@{
        Name='openclaw (separate runtime)'; Title='-'; Username=$username
        Level=$level; Poller='n/a (gateway)'; Pending=$pending; Supervisor='-'
        Note='read-only; managed by OpenClaw, not this tool'
    }
}

function Show-Health([object[]]$rows) {
    $color = @{ OK = 'Green'; WARN = 'Yellow'; STOPPED = 'Red' }
    Write-Host ''
    Write-Host ('{0,-28} {1,-8} {2,-18} {3,-8} {4,-10} {5}' -f 'BOT','STATE','POLLER','PENDING','SUPERVISOR','NOTE') -ForegroundColor White
    Write-Host ('-' * 110) -ForegroundColor DarkGray
    foreach ($r in $rows) {
        $c = $color[$r.Level]; if (-not $c) { $c = 'Gray' }
        Write-Host ('{0,-28} {1,-8} {2,-18} {3,-8} {4,-10} {5}' -f `
            $r.Name, $r.Level, $r.Poller, ("$($r.Pending)"), $r.Supervisor, $r.Note) -ForegroundColor $c
    }
    Write-Host ''
}

function Show-Toast([string]$title, [string]$msg) {
    try {
        if (Get-Module -ListAvailable -Name BurntToast) {
            Import-Module BurntToast -ErrorAction Stop
            New-BurntToastNotification -Text $title, $msg | Out-Null
            return
        }
    } catch {}
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $n = New-Object System.Windows.Forms.NotifyIcon
        $n.Icon = [System.Drawing.SystemIcons]::Warning
        $n.BalloonTipTitle = $title; $n.BalloonTipText = $msg
        $n.Visible = $true; $n.ShowBalloonTip(8000)
        Start-Sleep -Milliseconds 200; $n.Dispose()
    } catch {}
}

function Get-TabFragment([object]$bot) {
    # Returns a single wt 'new-tab' fragment. Bot names/titles have no spaces,
    # and the script path has no spaces, so no nested quoting is needed.
    $watch = Join-Path $ScriptDir 'Watch-Channel.ps1'
    $title = if ($bot.tabTitle) { $bot.tabTitle } else { "tg:$($bot.name)" }
    $title = $title -replace '\s',''
    return "new-tab --title $title pwsh -NoExit -NoProfile -ExecutionPolicy Bypass -File $watch -Name $($bot.name)"
}

switch ($Action) {

    { $_ -in 'doctor','status' } {
        $rows = @(); foreach ($b in $bots) { $rows += Get-BotHealth $b }
        $oc = Get-OpenClawHealth; if ($oc) { $rows += $oc }
        Show-Health $rows
    }

    'monitor' {
        $rows = @(); foreach ($b in $bots) { $rows += Get-BotHealth $b }

        # Auto-heal: a bot is STOPPED and has NO supervisor (e.g. its tab was
        # closed) -> relaunch its tab. Guard on Test-SupervisorRunning so we
        # never double-start a bot that is merely mid-restart (would 409).
        # Skip 'no token' stops (config error, not something a restart fixes).
        $healed = @()
        foreach ($b in $bots) {
            $h = $rows | Where-Object { $_.Name -eq $b.name }
            if ($h.Level -eq 'STOPPED' -and (Get-Token $b) -and -not (Test-SupervisorRunning $b.name)) {
                try { Start-Process wt -ArgumentList ('-w 0 ' + (Get-TabFragment $b)); $healed += $b.name } catch {}
            }
        }

        $fleet = Join-Path $StateRoot 'fleet-status.json'
        $payload = [ordered]@{ checkedAt = (Get-Date).ToString('o'); healed = $healed; bots = $rows }
        $payload | ConvertTo-Json -Depth 5 | Set-Content -Path $fleet -Encoding UTF8

        $bad = $rows | Where-Object { $_.Level -ne 'OK' -and $_.Name -notlike 'openclaw*' }
        if ($bad -or $healed) {
            $lines = @()
            if ($healed) { $lines += "auto-restarted: $($healed -join ', ')" }
            $lines += ($bad | ForEach-Object { "$($_.Name): $($_.Level) — $($_.Note)" })
            $summary = $lines -join "`n"
            Show-Toast 'Telegram bots: action taken' $summary
            $mlog = Join-Path $StateRoot 'monitor.log'
            Add-Content -Path $mlog -Value ("{0:o}`n{1}" -f (Get-Date), $summary) -Encoding UTF8
        }
        Show-Health $rows
    }

    'start-all' {
        $frag = $bots | ForEach-Object { Get-TabFragment $_ }
        $cmd = $frag -join ' ; '
        Write-Host "Opening Windows Terminal with $($bots.Count) titled tabs..." -ForegroundColor Cyan
        Start-Process wt -ArgumentList $cmd
    }

    'start' {
        if (-not $Name) { throw "start needs -Name" }
        $b = Get-Bot $Name
        # -w 0 attaches the tab to the existing fleet window instead of opening a new one.
        Start-Process wt -ArgumentList ('-w 0 ' + (Get-TabFragment $b))
    }

    { $_ -in 'stop','stop-all' } {
        $targets = if ($Action -eq 'stop-all') { $bots } else { @(Get-Bot $Name) }
        foreach ($b in $targets) {
            $stateDir = Join-Path $StateRoot $b.name
            $pidFile = Join-Path $stateDir 'bot.pid'
            if (Test-Path $pidFile) {
                $p = [int]((Get-Content $pidFile -Raw).Trim())
                if (Test-PidAlive $p) { Stop-Process -Id $p -Force -ErrorAction SilentlyContinue; Write-Host "stopped poller pid $p ($($b.name))" -ForegroundColor Yellow }
            }
            # supervisors run Watch-Channel.ps1 -Name <b>; stop those pwsh too
            Get-CimInstance Win32_Process -Filter "Name='pwsh.exe' OR Name='powershell.exe'" |
                Where-Object { $_.CommandLine -match "Watch-Channel.ps1.*-Name\s+'?$($b.name)\b" } |
                ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue; Write-Host "stopped supervisor pid $($_.ProcessId) ($($b.name))" -ForegroundColor Yellow }
        }
    }

    'restart' {
        if (-not $Name) { throw "restart needs -Name" }
        & $PSCommandPath stop -Name $Name
        Start-Sleep 2
        & $PSCommandPath start -Name $Name
    }

    'logs' {
        if (-not $Name) { throw "logs needs -Name" }
        $b = Get-Bot $Name
        if ($Mcp) {
            $slug = ($b.repoRoot -replace '[:\\/]', '-') -replace '^-+',''
            $dir = Join-Path $env:LOCALAPPDATA "claude-cli-nodejs\Cache\$slug\mcp-logs-plugin-telegram-telegram"
            $f = Get-ChildItem $dir -Filter '*.jsonl' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
            if (-not $f) { Write-Host "No plugin mcp-logs under $dir" -ForegroundColor Yellow; break }
            Write-Host "== $($f.FullName) ==" -ForegroundColor Cyan
            if ($Follow) { Get-Content $f.FullName -Tail $Tail -Wait } else { Get-Content $f.FullName -Tail $Tail }
        } else {
            $f = Get-ChildItem (Join-Path $StateRoot "$Name\logs") -Filter 'supervisor-*.log' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
            if (-not $f) { Write-Host "No supervisor log yet for $Name" -ForegroundColor Yellow; break }
            Write-Host "== $($f.FullName) ==" -ForegroundColor Cyan
            if ($Follow) { Get-Content $f.FullName -Tail $Tail -Wait } else { Get-Content $f.FullName -Tail $Tail }
        }
    }

    'ids' {
        foreach ($b in $bots) {
            $acc = Join-Path $StateRoot "$($b.name)\access.json"
            Write-Host "== $($b.name) ==" -ForegroundColor Cyan
            if (Test-Path $acc) {
                $j = Get-Content $acc -Raw | ConvertFrom-Json
                Write-Host "  policy   : $($j.dmPolicy)"
                Write-Host "  allowFrom: $((@($j.allowFrom)) -join ', ')"
                $pend = $j.pending.PSObject.Properties
                if ($pend) { $pend | ForEach-Object { Write-Host "  pending  : code=$($_.Name) -> $($_.Value | ConvertTo-Json -Compress)" -ForegroundColor Yellow } }
            } else { Write-Host "  (no access.json yet)" -ForegroundColor DarkGray }
        }
    }

    'allow' {
        if (-not $Name -or -not $Value) { throw "allow needs -Name and -Value <numericUserId>" }
        $acc = Join-Path $StateRoot "$Name\access.json"
        New-Item -ItemType Directory -Force -Path (Split-Path $acc) | Out-Null
        $j = if (Test-Path $acc) { Get-Content $acc -Raw | ConvertFrom-Json } else { [pscustomobject]@{ dmPolicy='pairing'; allowFrom=@(); groups=@{}; pending=@{} } }
        $list = [System.Collections.Generic.List[string]]::new()
        @($j.allowFrom) | Where-Object { $_ } | ForEach-Object { $list.Add("$_") }
        if (-not $list.Contains("$Value")) { $list.Add("$Value") }
        $j.allowFrom = $list.ToArray()
        $j | ConvertTo-Json -Depth 6 | Set-Content -Path $acc -Encoding UTF8
        Write-Host "Added $Value to $Name allowlist. (plugin re-reads access.json live; no restart needed)" -ForegroundColor Green
    }

    'policy' {
        if (-not $Name -or -not $Value) { throw "policy needs -Name and -Value (pairing|allowlist|disabled)" }
        if ($Value -notin 'pairing','allowlist','disabled') { throw "policy must be pairing|allowlist|disabled" }
        $acc = Join-Path $StateRoot "$Name\access.json"
        New-Item -ItemType Directory -Force -Path (Split-Path $acc) | Out-Null
        $j = if (Test-Path $acc) { Get-Content $acc -Raw | ConvertFrom-Json } else { [pscustomobject]@{ dmPolicy='pairing'; allowFrom=@(); groups=@{}; pending=@{} } }
        $j.dmPolicy = $Value
        $j | ConvertTo-Json -Depth 6 | Set-Content -Path $acc -Encoding UTF8
        Write-Host "$Name dmPolicy set to '$Value'." -ForegroundColor Green
    }
}
