# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`server-pulse` is a pure-bash Linux server health monitor that sends Telegram alerts when disk, inode, RAM, swap, load, CPU, OOM events, Docker containers, or systemd units cross thresholds. No language runtime, no daemon — a `oneshot` script invoked by a systemd timer every 2 minutes. Targets bash 4+ and systemd.

## Commands

```bash
# Lint (CI gate — run before every commit/PR; the GitHub Action blocks on it)
shellcheck -x -e SC1091 install.sh bin/server-pulse lib/**/*.sh

# Run a single cycle locally without installing (override config/state paths)
SP_CONFIG_PATH=./config/config.example.env SP_STATE_DIR=/tmp/sp-state ./bin/server-pulse run

# CLI surface
./bin/server-pulse run|test|status|silence <30m|2h|1d>|unsilence|version
```

There is **no build step and no test suite** (a bats suite is on the roadmap, not present). Verification is shellcheck + manual smoke runs.

## Runtime layout (installed)

- `/opt/server-pulse` — installed code tree (`bin/`, `lib/`, `systemd/`, `config/`).
- `/usr/local/bin/server-pulse` — symlink to `bin/server-pulse`.
- `/etc/server-pulse/config.env` — operator config, **enforced `chmod 600`, owned by the running uid**.
- `/var/lib/server-pulse/` — runtime state (`chmod 700`): `state/*.state`, `silence`, `oom.seen`.

Both `SP_CONFIG_PATH` and `SP_STATE_DIR` are overridable via env — use them to run against a checkout without touching system paths.

## Architecture

Single entrypoint `bin/server-pulse` sources every `lib/**/*.sh` at startup (`SP_ROOT` is resolved from the script's real path so it works both from a checkout and from `/opt`), then dispatches on the subcommand. `run` calls each `sp_check_*` in sequence.

The data flow is uniform across all checks:

```
sp_check_<name>  →  sp_state_dispatch(id, status, value, message)  →  _sp_state_notify  →  sp_notify → sp_telegram_send
                                                                                          ↘  sp_mc_report → POST /api/ingest/server
```

Layers:

- **`lib/config.sh`** — `sp_config_load` validates the config file is a regular (non-symlink) file owned by `$EUID` with mode 400/440/600/640 *before* sourcing it (it runs arbitrary shell), then applies defaults (`sp_config_apply_defaults`) and validates types (`sp_config_validate`). All tunables are env vars; defaults live here, not in the example config.
- **`lib/checks/*.sh`** — one file per check, each defining `sp_check_<name>()`. A check reads the metric, decides `OK`/`WARN`/`CRIT` against the threshold env vars, and emits results via `sp_state_dispatch`. Each gated by its own `CHECK_<NAME>` toggle (early `return 0` when off).
- **`lib/state.sh`** — the alert state machine. This is the core of the system. Each alertable entity gets a state file `state/<sanitized-id>.state`. `sp_state_dispatch` reads the previous status and decides whether to notify based on the `prev:new` transition (see below). It owns throttling, escalation, and RESOLVED.
- **`lib/notify/telegram.sh`** — `sp_notify` formats the severity header (`🚨 CRITICAL · <SERVER_NAME>`) and short-circuits on active silence; `sp_telegram_send` does the curl. **Secrets (bot token, proxy creds) go in a 0600 tempfile passed via `curl --config`, never on the command line** — other local users can read argv via `/proc`.
- **`lib/notify/mission-control.sh`** — `sp_mc_report` mirrors WARN/CRIT/RESOLVED into the Mission Control fleet timeline (`POST /api/ingest/server`). Optional (no-op unless `MC_URL`+`MC_TOKEN` are set), fire-and-forget (a failed POST never aborts the run), and **independent of silence** (the timeline records even when Telegram is muted). The bearer token goes in a `curl --config` tempfile like the Telegram notifier; the JSON payload is built without `jq` (pure bash). MC attributes the event by matching `SERVER_NAME` against `projects.host` — no slug is sent.
- **`lib/log.sh`** — timestamped stderr logging (captured by journald under systemd).

### State machine (lib/state.sh) — the part to understand before editing

A "check id" is a single alertable entity, e.g. `disk:/`, `memory:ram`, `docker:app`. One check function can dispatch many ids (one per mountpoint/container). The id is sanitized to `[a-zA-Z0-9_-]` for the filename; the original is stored inside the file for `status` display.

Transition behavior in `sp_state_dispatch`:

- `OK→WARN`, `OK→CRIT`, `WARN→CRIT` — notify immediately (new alert / escalation).
- `WARN→WARN`, `CRIT→CRIT` — notify only if `now - last_sent >= THROTTLE` (`WARN_THROTTLE_MIN` / `CRIT_THROTTLE_MIN`).
- `CRIT→WARN` — partial recovery, **no message**, but `last_sent` is retained so WARN throttling continues.
- `WARN→OK`, `CRIT→OK` — send RESOLVED (if `RESOLVED_NOTIFY=true`) then delete the state file.

Two deliberate invariants when touching this code:

1. **The throttle clock only advances on successful delivery.** A failed Telegram send writes `last_sent` unchanged (or `0` for a fresh alert) so the alert is retried next cycle instead of being silently throttled away. See `_sp_state_notify`'s return code handling.
2. **State clearing takes priority over the RESOLVED message.** On recovery the send is best-effort (`|| true`) and the file is deleted regardless — otherwise one failed send would pin a check in WARN/CRIT forever.

Silence (`silence`/`unsilence`) writes an expiry epoch to `state/../silence`; `sp_notify` checks `sp_silence_active` and suppresses delivery, but **state transitions still run** so you don't get a flood of stale alerts when silence expires.

### OOM check is special (lib/checks/oom.sh)

Unlike threshold checks, OOM scans `journalctl -k` for the last 15 minutes, dedups matched lines by SHA-1 against `oom.seen` (trimmed to 200 lines), and dispatches CRIT only for genuinely new events. This prevents re-alerting the same kill every cycle.

## Conventions

- Every file is `set -euo pipefail` (entrypoint) bash; functions are namespaced `sp_*`, internal helpers `_sp_*`.
- `bash` has no float math — load ratio comparison is done in `awk` (see `lib/checks/load.sh`). Follow that pattern for any fractional math.
- State writes are atomic: write to `<file>.tmp`, then `mv -f` (see `sp_state_write`).
- When adding a check: create `lib/checks/<name>.sh` with `sp_check_<name>()`, gate on a `CHECK_<NAME>` toggle, add its default in `sp_config_apply_defaults` (and validate it in `sp_config_validate`), `source` it in `bin/server-pulse`, and call it from `sp_cmd_run`. Dispatch results through `sp_state_dispatch` — never call `sp_notify` directly from a check.

**Mission Control** — this repo isn't pinned to a project yet. The `mission-control` MCP server is **dormant**: if asked to work through MC (or via `/mc`), confirm the slug with the user or via `get_fleet_digest`, then call `mc_help`.
