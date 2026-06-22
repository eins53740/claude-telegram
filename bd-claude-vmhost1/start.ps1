<#
.SYNOPSIS
    Launch the bd-claude@vmhost1 personal Telegram bot (single, supervised run).
.DESCRIPTION
    Thin shim - delegates to ..\Watch-Channel.ps1, which reads repoRoot / model /
    token for this bot from channels.json (single source of truth).
    Normal fleet start: ..\Channels.ps1 start-all. Ctrl+C to stop.
#>
[CmdletBinding()]
param()
$watch = Join-Path (Split-Path $PSScriptRoot -Parent) 'Watch-Channel.ps1'
& $watch -Name 'bd-claude-vmhost1'
