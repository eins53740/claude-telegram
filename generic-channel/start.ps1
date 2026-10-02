<#
.SYNOPSIS
    Launch the BD@SECIL Claude generic Telegram bot (single, supervised run).
.DESCRIPTION
    Thin shim - delegates to ..\Watch-Channel.ps1, which reads repoRoot / model /
    token for this bot (name: generic-channel) from channels.json. Token comes
    from this folder's .env. Normal fleet start: ..\Channels.ps1 start-all.
    Ctrl+C to stop.
#>
[CmdletBinding()]
param()
$watch = Join-Path (Split-Path $PSScriptRoot -Parent) 'Watch-Channel.ps1'
& $watch -Name 'generic-channel'
