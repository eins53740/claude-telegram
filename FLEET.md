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

## Tuning persona & permissions

Each bot has two knobs: **persona** (what it should do) and **permissions** (what
it's *allowed* to do unattended — a bot can't answer a permission prompt, so a
tool works only if it's on the allow list).

**Persona** — `<profileDir>\SYSTEM_PROMPT.md`. Edit, then `.\Channels.ps1 restart -Name <bot>`.

**Permissions — two layers (merged):**
1. `~/.claude/settings.json` — global baseline for **all** bots (`defaultMode: auto`). Today: Telegram reply/react, Canary read, personal GitHub read, GHE read.
2. `<repoRoot>\.claude\settings.local.json` — per-bot (machine-local, uncommitted). Adds `allow` / `deny` for just that bot. `deny` overrides `allow`.

Current per-bot extras (via each `repoRoot`'s settings.local.json):

| Bot | repoRoot | Extra (read) | Denied |
|-----|----------|--------------|--------|
| uns-ot-expert | `…\CodingAgentIgnition` | EMQX, Ignition ×3, SSH | EMQX `publish_message`, SSH `run_command` |
| bd-claude-vmhost1 | `D:\Github\BD` | EMQX, Ignition ×3, SSH, Gmail/Calendar | + Gmail `send`/`draft` |
| generic-channel | its profile dir | none (baseline only) | — |

How to change later:

```powershell
# give ONE bot a tool: add to "allow" in <repoRoot>\.claude\settings.local.json
#   a whole server:  "mcp__emqx-mcp"
#   one tool:        "mcp__ssh-uns-mcp__get_system_info"
# block a tool:      add to "deny" (wins over allow)
# all bots:          edit ~/.claude/settings.json
# then:
.\Channels.ps1 restart -Name <bot>
```

**Pending / available:** uns-ot-expert Jira/Confluence is blocked until the local
`atlassian-secil` MCP is configured (not installed yet) — then add its read tools
to that repo's settings.local.json. MS365 can be added to bd-vmhost1 the same way
(read tools only; deny send/draft).

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
