# BD Bots - service & task bundle

Production location: `C:\BD_Bots\`. Source bundle: `~\Downloads\Bot\`.

This folder manages the five bots under `\BD\Bots\` using a **split
architecture** - the two truly headless bots run as Windows services
via NSSM, the three Claude Code channel bots stay in Task Scheduler
(claude requires a TTY which services can't provide).

---

## Final architecture

```
NSSM services (truly headless, run even after restart-on-crash)
  BD.ClaudeTelegramBot       legacy Python long-poller, wraps `claude -p`
  BD.OpenClawGateway         Node HTTP gateway on port 18789

Task Scheduler under \BD\Bots\ (interactive session, RestartCount=999)
  BdClaudeVmhost1            personal Telegram channel
  ClaudeTelegramChannel      generic Telegram channel
  ClaudeUNSOTExpert          UNS-OT engineering Telegram channel
```

### Why the split?

claude.exe auto-detects "no TTY" when stdout is redirected and flips
into `--print` mode, which then errors out for lack of a prompt:

```
Error: Input must be provided either through stdin or as a prompt argument when using --print
```

NSSM captures stdout to a file, so claude sees no TTY -> services
crash-loop. Task Scheduler tasks run in your interactive desktop
session (real console, real TTY) so claude works normally. The 3
channel tasks get `RestartCount=999 / RestartInterval=PT1M` so they
recover from crashes comparably to NSSM.

The 2 headless bots (Python long-poller, Node HTTP) don't care about
TTY and run cleanly as services.

---

## Filesystem layout

```
C:\BD_Bots\
  install-services.ps1            install the 2 headless services
  uninstall-services.ps1          stop + remove the BD.* services
  revert-channels-to-tasks.ps1    revert the 3 channel bots to Task Scheduler
  manage.ps1                      day-to-day service control
  cutover-from-tasks.ps1          enable/disable the \BD\Bots\ tasks
  README.md                       this file
  bin\nssm.exe                    downloaded on first install
  logs\BD.<name>.{out,err}.log    per-service rotating logs (20 MiB)
```

---

## Service bot inventory (NSSM)

| Service | Wraps | Notes |
|---|---|---|
| `BD.ClaudeTelegramBot` | `pythonw D:\Github\BD\Agents\claude-telegram\claude_telegram_bot.py` | Predates the channel plugin; stateless `claude -p` wrapper per message. |
| `BD.OpenClawGateway` | `C:\Users\bsdias\.openclaw\gateway.cmd` | Node HTTP gateway on `localhost:18789`. Not a Claude channel. |

## Task bot inventory (\BD\Bots\)

| Task | Launcher | Notes |
|---|---|---|
| `BdClaudeVmhost1` | `D:\Github\BD\Agents\claude-telegram\bd-claude-vmhost1\start.ps1` | Personal channel, persona file, repo root `D:\Github\BD`. |
| `ClaudeTelegramChannel` | `D:\Github\BD\Agents\claude-telegram\generic-channel\start.ps1` | Plugin-managed token, no custom persona. |
| `ClaudeUNSOTExpert` | `D:\Github\SECIL\CodingAgentIgnition\channels\uns-ot-expert\start.ps1` | UNS-OT engineering persona, repo root = CodingAgentIgnition. |

All three delegate to a single launcher:
`D:\Github\BD\Agents\claude-telegram\Start-Channel.ps1`.

---

## Install (one-time)

```powershell
# Elevated
cd $env:USERPROFILE\Downloads\Bot       # or C:\BD_Bots once copied
.\install-services.ps1
# Prompts for your password (service logon account = current user).
```

Re-run with `-Force` to recreate existing services. If `nssm.cc` is
blocked: `winget install NSSM.NSSM` first, or drop `nssm.exe` into
`C:\BD_Bots\bin\` manually.

After install, the 3 channel tasks under `\BD\Bots\` are still enabled
from the original setup and will auto-launch on boot. Run the revert
script next so the 3 tasks get restart-on-failure and the 2 redundant
tasks (matching the new services) are disabled.

```powershell
.\revert-channels-to-tasks.ps1          # elevated
```

This script also handles the case where you previously tried to install
all 5 as services and ended up with 3 broken ones - it removes those
and re-enables the matching tasks.

---

## Day-to-day management

```powershell
.\manage.ps1 status                                # all BD.* services
.\manage.ps1 start   BD.ClaudeTelegramBot
.\manage.ps1 stop    BD.OpenClawGateway
.\manage.ps1 restart BD.ClaudeTelegramBot
.\manage.ps1 logs    BD.OpenClawGateway            # last 30 lines stdout + stderr
.\manage.ps1 logs    BD.ClaudeTelegramBot -Follow  # tail -f stdout
```

For the 3 channel tasks, use Task Scheduler tooling:

```powershell
Get-ScheduledTask -TaskPath '\BD\Bots\' | Where-Object State -ne 'Disabled' |
    Select-Object TaskName, State,
        @{N='Restart';E={ if ($_.Settings.RestartCount) {
            "$($_.Settings.RestartCount)x every $($_.Settings.RestartInterval)" } else {'-'} }} |
    Format-Table -AutoSize

Start-ScheduledTask -TaskName ClaudeUNSOTExpert -TaskPath '\BD\Bots\'
Stop-ScheduledTask  -TaskName ClaudeUNSOTExpert -TaskPath '\BD\Bots\'
```

---

## Manual run in a terminal (no service, no task)

For interactive debugging. Stop the matching service/task first or
Telegram will reject the second poller with `409 Conflict`.

| Bot | Manual command |
|---|---|
| ClaudeTelegramBot | `python D:\Github\BD\Agents\claude-telegram\claude_telegram_bot.py` |
| BdClaudeVmhost1 | `D:\Github\BD\Agents\claude-telegram\bd-claude-vmhost1\start.ps1` |
| ClaudeTelegramChannel | `D:\Github\BD\Agents\claude-telegram\generic-channel\start.ps1` |
| ClaudeUNSOTExpert | `D:\Github\SECIL\CodingAgentIgnition\channels\uns-ot-expert\start.ps1` |
| OpenClaw Gateway | `C:\Users\bsdias\.openclaw\gateway.cmd` |

The three channel scripts also accept `-SkipPermissions`. If a `.ps1`
is blocked by execution policy, prefix with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<path>\start.ps1"
```

---

## Uninstall

```powershell
.\uninstall-services.ps1                # stop + remove all BD.* services
.\uninstall-services.ps1 -PurgeRoot     # also delete C:\BD_Bots\
.\revert-channels-to-tasks.ps1 -Restore # re-install services + restore old task state
```

If you fully uninstall, re-enable all 5 tasks:

```powershell
Get-ScheduledTask -TaskPath '\BD\Bots\' | Enable-ScheduledTask
```

---

## Tuning

Edit `install-services.ps1` (the `$bots` array) to add/change a service.
Re-run with `-Force` to apply.

NSSM restart policy per service (set by the installer):

| nssm param | Value | Effect |
|---|---|---|
| `AppExit Default` | `Restart` | Relaunch on any exit code |
| `AppRestartDelay` | `5000` | 5 s between restarts |
| `AppThrottle` | `10000` | Mark as flapping if exits within 10 s |
| `AppRotateBytes` | `20971520` | Log rotation threshold (20 MiB) |

Live tweaks:

```powershell
C:\BD_Bots\bin\nssm.exe edit BD.OpenClawGateway        # GUI editor
C:\BD_Bots\bin\nssm.exe set  BD.OpenClawGateway AppRestartDelay 10000
```

Task restart-on-failure (set by `revert-channels-to-tasks.ps1`):

```powershell
$t = Get-ScheduledTask -TaskName ClaudeUNSOTExpert -TaskPath '\BD\Bots\'
$t.Settings.RestartCount    = 999
$t.Settings.RestartInterval = 'PT2M'    # ISO 8601 duration
Set-ScheduledTask -InputObject $t
```

---

## Troubleshooting

### Channel service "won't start, service did not return an error"
The TTY issue. Run `revert-channels-to-tasks.ps1` - that's why this
script exists.

### `Can't open service!` during install or `nssm start`
`nssm` writes this to stderr for missing services (existence check)
or when called unelevated. The installer uses `Get-Service` for the
probe; for ad-hoc nssm commands, run from an elevated shell.

### Em-dashes / non-ASCII in `.ps1` files
Windows PowerShell 5.1 reads `.ps1` as cp1252 without BOM. UTF-8
non-ASCII characters corrupt to mojibake and can break string
termination. **Keep every `.ps1` ASCII-only.** Verify after edits:

```powershell
Select-String -Path *.ps1 -Pattern '[^\x00-\x7F]' -AllMatches
```

### `nssm.cc 503 Service Temporarily Unavailable`
Transient. Retry, or `winget install NSSM.NSSM` and copy the binary
into `C:\BD_Bots\bin\nssm.exe`.

### Service installed but `StartType=Disabled`
Rare race during nssm install:

```powershell
# Elevated
Set-Service -Name BD.<ServiceName> -StartupType Automatic
```

### `409 Conflict: terminated by other getUpdates request`
Two pollers on the same Telegram bot token. Find and stop the duplicate:

```powershell
Get-Service -Name 'BD.*'                           # running services
Get-ScheduledTask -TaskPath '\BD\Bots\' |
    Where-Object State -eq 'Running'               # running tasks
```

### Service won't start, err.log empty
Check the Windows event log:

```powershell
Get-WinEvent -LogName Application -MaxEvents 50 |
    Where-Object ProviderName -eq 'nssm' |
    Select-Object TimeCreated, Id, Message | Format-Table -Wrap
```

Common causes: wrong service password (re-run installer with `-Force`),
launcher script missing, dependency not on PATH for the service account.
