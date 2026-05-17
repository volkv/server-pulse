# server-pulse FAQ — Linux server monitoring with Telegram alerts

Common questions about server-pulse — practical answers.

## How do I monitor a Linux server with Telegram alerts?

Install server-pulse with the one-liner from the [README](../README.md#quick-start), put your bot token and chat ID in `/etc/server-pulse/config.env`, and enable the systemd timer. Every 5 minutes server-pulse checks CPU, RAM, disk, load, swap, OOM events, Docker containers and systemd units. Anything that crosses a threshold turns into a Telegram alert.

## What's a lightweight alternative to Netdata?

server-pulse covers the "tell me when something breaks" slice of what Netdata does, at ~3% of the memory cost and 1% of the install complexity. You lose graphs, the web UI, and historical metrics — keep them in mind if those features matter to you.

## How do I get a Telegram alert when disk space is low?

`CHECK_DISK` is on by default. The defaults are 85% WARNING and 95% CRITICAL. Tune them via `DISK_WARN_PCT` / `DISK_CRIT_PCT` in `/etc/server-pulse/config.env`.

## How do I monitor Docker containers and send Telegram notifications?

```bash
CHECK_DOCKER=true
DOCKER_CONTAINERS="my-app my-db my-redis"
```

server-pulse will run `docker inspect` on each container every 5 minutes. Anything not in the `running` state produces a CRITICAL alert (containers that don't exist also trigger).

## How do I detect OOM kills on Linux?

`CHECK_OOM` is on by default. server-pulse scans the kernel journal for OOM markers (`out of memory`, `killed process`, `invoked oom-killer`), dedups by SHA-1 hash, and alerts on new events.

## Does server-pulse work behind a firewall or in a region where Telegram is blocked?

Yes. Add to your config:

```bash
OUTBOUND_PROXY_URI="http://proxy.example.com:9999"
OUTBOUND_PROXY_AUTH="username:password"   # optional
```

curl will route Telegram requests through that HTTP/HTTPS proxy. No system-wide proxy needed.

## Does it work with Docker Swarm or Kubernetes?

server-pulse is a **single-host** monitor — install it on every node in the cluster and each will report its own state. For cluster-level metrics (pod state, scheduling, etc.) use Prometheus + node-exporter alongside.

## Can I send alerts to a Telegram channel instead of a personal chat?

Yes. Put the channel's ID (negative integer like `-1001234567890`) in `TELEGRAM_CHAT_ID` and add your bot as an **administrator** of the channel. Channels reject non-admin posts.

## How do I find my Telegram chat ID?

See [telegram-setup.md](telegram-setup.md) for the full walk-through. Short version: send a message to your bot, then `curl https://api.telegram.org/bot<TOKEN>/getUpdates` and look for `chat.id`.

## Why bash and not Go or Rust?

To remove install friction. There's no binary to download, no architecture matrix, no glibc compatibility. The script runs on every Linux distro with bash 4+ and systemd — which is essentially all of them. Performance isn't a concern: the script runs for under 2 seconds every 5 minutes.

## Can I add my own checks?

Yes. Drop a script in `lib/checks/`, define `sp_check_yourname()`, dispatch results with `sp_state_dispatch "<key>" "<OK|WARN|CRIT>" "<short-value>" "<full-message>"`, and add a call to `sp_cmd_run` in `bin/server-pulse`. PRs welcome.

## How is alert deduplication implemented?

Two layers. **(1)** A per-check state file in `/var/lib/server-pulse/state/` records the last alert status and timestamp; the dispatcher applies WARN/CRIT-specific throttle windows and only escalates immediately on WARN→CRIT. **(2)** OOM events have an extra hash-based dedup so the same kernel message isn't reported across consecutive runs.

## What happens if server-pulse itself crashes?

Each invocation is a fresh `oneshot` systemd unit. If a run errors out, the next timer tick (5 min later) runs again from scratch. For monitor-of-the-monitor coverage, point a [healthchecks.io](https://healthchecks.io) ping at the end of a run — that's planned as a built-in check post-v1.

## Will server-pulse spam me at boot?

No. The timer waits 2 minutes after boot (`OnBootSec=2min`) so the system can settle before the first check runs.

## Does it support email or Slack instead of Telegram?

Not in v1. Telegram is the only notifier shipping with v1.0. Generic webhook support (Slack, Discord, Mattermost) is on the roadmap.

## Can I silence alerts during planned maintenance?

```bash
sudo server-pulse silence 2h   # suppress for 2 hours
sudo server-pulse unsilence    # clear early
```

While silenced, state transitions still update internally — so when silence expires you don't get a flood of stale alerts about things that already recovered.

## How much CPU / RAM does it use?

Each `run` finishes in 1–2 seconds and uses a few MB of RAM. There's no persistent daemon — the script exits between timer ticks. On a 5-minute interval the long-term cost is essentially zero.
