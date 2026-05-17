# server-pulse — Lightweight Linux server monitoring with Telegram alerts

[![shellcheck](https://github.com/volkv/server-pulse/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/volkv/server-pulse/actions/workflows/shellcheck.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Bash 4+](https://img.shields.io/badge/bash-4%2B-89e051?logo=gnubash&logoColor=white)
![systemd](https://img.shields.io/badge/systemd-required-orange)

> **server-pulse** is a tiny Linux server health monitor that sends Telegram alerts before your **VPS**, **dedicated server**, or **homelab** box runs out of disk, memory, CPU, or Docker services. Pure bash, no language runtime, no long-running daemon. 60-second install.

Drop it on any Linux machine — a $5 VPS, a bare-metal dedic, a Raspberry Pi, a cloud instance — and you'll know **the moment something starts going wrong**, not after the site goes down.

```
🚨 CRITICAL · respawn-prod
Disk usage: 96% on / (free: 3.1G / 79G)

⚠️ WARNING · homelab-nas
Load average: 4.21 (5min) on 2 cores  →  2.1x

✅ RESOLVED · respawn-prod
Disk usage: 76% on / (free: 19G / 79G)
```

---

## Why server-pulse

Most monitoring stacks are designed for fleets, dashboards, and SREs. If you run a handful of servers and just want to know **when something breaks**, you don't need Prometheus, Grafana, or a 150 MB Netdata daemon. You need a script.

server-pulse is that script — but with the production-grade bits (proper alert throttling, OOM dedup, secure config, systemd integration) already done for you.

- **No language runtime, no daemon.** Just bash, curl, awk, grep, sed, coreutils, systemd. No Python, no Go binary, no database, no long-running process. Everything you already have on any Linux box.
- **60-second install.** One curl command, edit a config, enable a timer.
- **No noisy alerts.** Built-in throttling, WARN→CRITICAL escalation, RESOLVED messages.
- **No false positives on OOM.** Journal dedup so the same kill isn't reported every 5 minutes.
- **Telegram-native.** Just a bot token and a chat ID. Supports outbound HTTP proxy for blocked regions.
- **No central collector.** Each host runs a oneshot script on a 5-minute systemd timer and sends its own alerts. Add a server without changing anything central.

---

## Features

- ✅ **Disk** usage per mountpoint (with sane defaults for `tmpfs`, `overlay`, etc.)
- ✅ **Inode** usage per mountpoint
- ✅ **RAM** usage (via `MemAvailable`, not just "free")
- ✅ **Swap** usage
- ✅ **Load average** (5 min) normalized by CPU count
- ✅ **CPU** usage (instant 1-second sample of `/proc/stat`)
- ✅ **OOM killer** events from kernel journal, deduplicated
- ✅ **Docker containers** — allowlist of containers that must be running
- ✅ **systemd units** — allowlist of units that must be active
- 🔔 **Telegram** notifications with optional outbound HTTP proxy
- 🎚 **WARN / CRITICAL / RESOLVED** state machine with throttling and escalation
- 🔕 **Silence** command for planned maintenance
- 🛠 **systemd timer** for periodic execution (5-minute default, randomized delay)
- 🔒 **Secure config** — installer enforces `chmod 600` on the file with your bot token

---

## Quick start

### Option A: one-liner install

```bash
curl -fsSL https://raw.githubusercontent.com/volkv/server-pulse/main/install.sh | sudo bash
```

### Option B: from a clone

```bash
git clone https://github.com/volkv/server-pulse.git
cd server-pulse
sudo ./install.sh
```

Either way, the next three steps are the same:

```bash
# 1. Edit the config — set TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID at minimum.
sudo $EDITOR /etc/server-pulse/config.env

# 2. Send a test alert to verify Telegram delivery.
sudo server-pulse test

# 3. Enable the periodic check.
sudo systemctl enable --now server-pulse.timer
```

That's it. The timer fires every 5 minutes (with a 30-second randomized delay so a fleet of servers doesn't hammer the Telegram API at the same second).

---

## What it monitors

| Check | Source | Default WARN | Default CRIT |
|---|---|---|---|
| `disk` | `df -hP` per mountpoint | 85% | 95% |
| `inode` | `df -iP` per mountpoint | 85% | 95% |
| `ram` | `/proc/meminfo` (MemAvailable) | 85% | 95% |
| `swap` | `/proc/meminfo` (SwapFree) | 50% | 80% |
| `load` | `/proc/loadavg` (5 min) ÷ `nproc` | 1.5× | 3.0× |
| `cpu` | `/proc/stat` (1 s delta) | 85% | 95% |
| `oom` | `journalctl -k` | — | any event |
| `docker` | `docker inspect` (allowlist) | — | not `running` |
| `systemd` | `systemctl is-active` (allowlist) | — | not `active` |

All thresholds and toggles are env vars in `/etc/server-pulse/config.env`. See [docs/checks.md](docs/checks.md) and [docs/configuration.md](docs/configuration.md) for the full reference.

---

## CLI

```bash
server-pulse run                  # one cycle (this is what the timer calls)
server-pulse test                 # send a test message
server-pulse status               # show current alert state
server-pulse silence 1h           # suppress alerts for 1 hour (use s/m/h/d)
server-pulse unsilence            # clear an active silence
server-pulse version
```

`silence` is handy during planned maintenance — state transitions still update internally, so once silence expires you don't get a flood of stale alerts.

---

## Telegram bot setup

Short version:

1. Talk to [`@BotFather`](https://t.me/BotFather) → `/newbot` → copy the token.
2. Add the bot to your channel/group as an **administrator** (channels won't work otherwise), or just chat with it directly.
3. Get your chat ID:
   - For a user: send any message to your bot, then `curl https://api.telegram.org/bot<TOKEN>/getUpdates`
   - For a channel: forward a message from the channel to `@userinfobot`
4. Put `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID` into `/etc/server-pulse/config.env`.

Full walk-through: [docs/telegram-setup.md](docs/telegram-setup.md).

### Behind a firewall / blocked region

If `api.telegram.org` is unreachable from your server (e.g. RKN-blocked):

```bash
OUTBOUND_PROXY_URI="http://proxy.example.com:9999"
OUTBOUND_PROXY_AUTH="username:password"   # optional
```

curl uses the proxy for all Telegram requests — no system-wide proxy needed.

---

## Multi-server

Each host runs its own `server-pulse.timer` and pushes alerts to **the same Telegram chat**. The `SERVER_NAME` field in every message tells you which box is unhappy:

```
🚨 CRITICAL · web-01
Disk usage: 96% on /

⚠️ WARNING · db-prod
Swap usage: 64% (2.5 GB / 4.0 GB)
```

No aggregator, no pull-based discovery, no central agent. If you have 10 servers, you install on all 10. The same channel works fine for a fleet.

---

## Footprint

server-pulse is a oneshot script, not a daemon. On a typical Ubuntu/Debian host one run takes 1–2 seconds and exits; the process holds about 10–15 MB of RAM only while running and nothing in between cycles. There is no background process between timer ticks.

Storage on disk is negligible — the installed tree under `/opt/server-pulse` is a few hundred KB; runtime state files in `/var/lib/server-pulse` are a handful of bytes per active alert.

---

## How it compares

| | **server-pulse** | Netdata | Monit | Prometheus + Alertmanager | Glances |
|---|---|---|---|---|---|
| Install time | **60s** | ~5 min | ~10 min | 30+ min | ~2 min |
| RAM footprint | **~10–15 MB (per run, none idle)** | ~150 MB resident | ~10 MB | ~300 MB+ | ~50 MB |
| Language runtime | **none** | bundled binaries | none | Go runtime | Python |
| Telegram alerts | **built-in** | plugin | external script | via Alertmanager | none |
| Outbound proxy support | **built-in** | manual | manual | manual | n/a |
| Historical graphs | no | yes | no | yes (Grafana) | live only |
| Web UI | no | yes | no | yes | curses |
| Config | env file | many files | DSL | YAML | INI |
| Best for | **"tell me when broken"** | "show me everything" | classic process supervision | metrics + dashboards | live CLI dashboard |

Detailed comparison: [docs/comparison.md](docs/comparison.md).

---

## FAQ

### How do I monitor a Linux server with Telegram alerts?

Install server-pulse via the curl one-liner above, drop your bot token in the config, and enable the systemd timer. Every 5 minutes server-pulse checks disk, RAM, CPU, load, swap, OOM events, Docker containers, and systemd units, and sends a Telegram alert whenever a metric crosses a threshold.

### What is a lightweight alternative to Netdata for Telegram alerts?

If you don't need real-time graphs, a web UI, or a metrics history, server-pulse covers the "tell me when something breaks" slice of what Netdata does — at a tiny fraction of the RAM cost and a 60-second install. You give up graphs and historical data; you get a bash script with no daemon.

### How do I monitor disk space on Linux and send Telegram alerts?

`CHECK_DISK=true` is on by default. server-pulse runs `df` every 5 minutes on every non-virtual mountpoint and sends a Telegram WARNING at 85% and a CRITICAL at 95%. Override the thresholds via `DISK_WARN_PCT` and `DISK_CRIT_PCT` in `/etc/server-pulse/config.env`.

### How do I monitor CPU and RAM on a VPS with Telegram notifications?

CPU and memory checks are on by default. CPU is sampled over a 1-second window of `/proc/stat`; RAM is measured against `MemAvailable` from `/proc/meminfo`. Defaults: WARNING at 85%, CRITICAL at 95% for both. Tune with `CPU_WARN_PCT`, `CPU_CRIT_PCT`, `RAM_WARN_PCT`, `RAM_CRIT_PCT`.

### How do I monitor Docker containers with a bash script?

Set `CHECK_DOCKER=true` and `DOCKER_CONTAINERS="app db redis"` in `/etc/server-pulse/config.env`. server-pulse uses `docker inspect` to verify each container is in the `running` state; anything else (`exited`, `restarting`, missing) raises a CRITICAL Telegram alert.

### How do I get alerts for Linux OOM killer events?

`CHECK_OOM=true` is on by default. server-pulse scans `journalctl -k` for `killed process` / `out of memory` / `invoked oom-killer` messages every 5 minutes, deduplicates by SHA-1 hash of the matched line, and sends one CRITICAL alert per new event.

### Does server-pulse work behind a corporate firewall or in a blocked region?

Yes. Set `OUTBOUND_PROXY_URI` (and optionally `OUTBOUND_PROXY_AUTH`) in the config and curl will route all Telegram requests through that HTTP/HTTPS proxy.

### Does it work with Docker Swarm or Kubernetes?

server-pulse is a **single-host** monitor. For cluster-wide metrics use Prometheus + node-exporter. For single-host monitoring of nodes in a cluster, server-pulse works fine and complements cluster-level tooling.

### Can I send alerts to a Telegram channel instead of a personal chat?

Yes — put the channel's numeric ID (e.g. `-1001234567890`) in `TELEGRAM_CHAT_ID`. Make sure your bot is an **administrator** of the channel.

### Why bash and not Go or Rust?

To remove the install friction. There's no binary to download, no architecture matrix, no glibc version to worry about. The script works on every Linux distro that has bash 4+ and systemd, which is essentially all of them.

### Can I add my own checks?

Drop a file in `lib/checks/`, define a `sp_check_yourname()` function, dispatch results via `sp_state_dispatch`, and add the call to `sp_cmd_run` in `bin/server-pulse`. PRs welcome.

---

## Roadmap

Planned for future versions (not in v1):

- HTTP / TCP port / SSL-certificate-expiry checks
- Heartbeat (push to healthchecks.io to detect a dead monitor)
- Generic webhook notifier (Discord, Slack, Mattermost)
- Optional bats-based test suite
- Configurable per-mountpoint thresholds

---

## Contributing

Issues and PRs welcome. Please run `shellcheck -x -e SC1091 install.sh bin/server-pulse lib/**/*.sh` before submitting — CI will block merges on shellcheck failures.

---

## License

[MIT](LICENSE) © 2026 volkv
