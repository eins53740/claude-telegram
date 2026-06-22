# Claude Telegram Bot Fleet

Run several `claude --channels` Telegram bots side by side on one machine, each
in its own titled terminal tab, supervised, monitored, and self-healing.

> **Why this exists:** the `telegram@claude-plugins-official` plugin keeps its
> token, allowlist (`access.json`) and single-instance lock (`bot.pid`) in **one
> shared state dir** (`~/.claude/channels/telegram`). Every channel session used
> it, so each start SIGTERMed the previous poller (Telegram allows one
> `getUpdates` consumer per token) — only one bot stayed alive. The fix is one
> **`TELEGRAM_STATE_DIR` per bot**.

## Files

| File | Role |
|------|------|
| `channels.json` | Manifest — single source of truth: `name`, `profileDir`, `repoRoot`, `model`, `tabTitle`. |
| `Start-Channel.ps1` | Launch ONE bot, foreground, with its isolated `TELEGRAM_STATE_DIR`. |
| `Watch-Channel.ps1` | Supervisor: titled tab, restart-on-exit, `status.json` heartbeat, single-instance guard. |
| `Channels.ps1` | Management CLI (below). |

A **bot profile** is a folder with `.env` (`TELEGRAM_BOT_TOKEN=…`, gitignored)
and optional `SYSTEM_PROMPT.md` (persona). State lives in
`~/.claude/channels/<name>/` (`access.json`, `bot.pid`, `status.json`, `logs/`).

## Commands

```powershell
.\Channels.ps1 doctor                       # health table: OK / WARN / STOPPED
.\Channels.ps1 start-all                     # open the fleet (one titled tab per bot)
.\Channels.ps1 start   -Name <bot>           # one bot
.\Channels.ps1 stop    -Name <bot>           # stop one (stop-all for everything)
.\Channels.ps1 restart -Name <bot>
.\Channels.ps1 logs    -Name <bot> -Follow   # supervisor log (-Mcp for plugin stderr)
.\Channels.ps1 monitor                       # health sweep -> fleet-status.json, toast, AUTO-HEAL
.\Channels.ps1 ids                           # allowlists + pending pairings
.\Channels.ps1 allow   -Name <bot> -Value <numericUserId>
.\Channels.ps1 policy  -Name <bot> -Value allowlist   # pairing|allowlist|disabled
```

`start`/`start-all` skip bots that already have a running supervisor, so they
never create a duplicate poller.

## Autostart & monitoring (Windows)

- **`\BD\Bots\ClaudeTgFleet`** — at logon (+30 s) runs `Channels.ps1 start-all`.
- **`\BD\Bots\ClaudeTgFleetMonitor`** — every 5 min runs `Channels.ps1 monitor`:
  writes `~/.claude/channels/fleet-status.json`, toasts on problems, and
  **auto-restarts any STOPPED bot whose supervisor is gone** (e.g. a closed tab).

**Two recovery layers:** (1) claude crashes but the tab lives → supervisor
restarts in ~2 s; (2) tab/window closed or reboot → monitor auto-heals within
≤5 min. A single-instance guard keeps these from ever double-starting a bot.

> Because auto-heal is on, a bot you stop deliberately returns within ≤5 min.
> To keep one down: disable `ClaudeTgFleetMonitor` or remove it from `channels.json`.

## Access policy

Default `pairing` captures unknown numeric IDs; switch to `allowlist` once your
IDs are in (drops strangers silently). A Telegram numeric ID identifies an
**account**, not a device. Capture one via `@userinfobot`, then `allow`.

## Add a bot

1. `@BotFather` → new bot → token.
2. Create a profile folder with `.env` (token) + optional `SYSTEM_PROMPT.md` + `.gitignore` (`.env`).
3. Add an entry to `channels.json` (unique `name`, distinct `repoRoot` so logs stay separate).
4. `.\Channels.ps1 allow -Name <bot> -Value <yourId>` then `.\Channels.ps1 start -Name <bot>`.

## Deploy on Linux

The plugin is cross-platform; the supervisor layer is Windows-specific. Per bot,
set `TELEGRAM_STATE_DIR=$HOME/.claude/channels/<bot>` + `TELEGRAM_BOT_TOKEN`, run
`claude --channels …` under a `tmux` window or a `systemd --user` service with
`Restart=always`. One state dir per bot, never shared — that single rule is what
keeps tokens, allowlists and pollers from colliding.
