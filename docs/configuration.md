# Configuration reference

server-pulse reads a single shell-format env file at `/etc/server-pulse/config.env`. The installer creates it from `config/config.example.env` and locks it to `chmod 600`.

For per-check details (what each threshold means, how alerts are produced), see [checks.md](checks.md).

## File location & permissions

| Path | Purpose |
|---|---|
| `/etc/server-pulse/config.env` | Configuration (you edit this) |
| `/etc/systemd/system/server-pulse.{service,timer}` | systemd units |
| `/opt/server-pulse/` | Installed scripts (bin/lib/systemd/config) |
| `/usr/local/bin/server-pulse` | Symlink to the script |
| `/var/lib/server-pulse/` | Runtime state (`state/`, `oom.seen`, `silence`) |

The config must be readable by root only. server-pulse refuses to start otherwise:

```bash
sudo chown root:root /etc/server-pulse/config.env
sudo chmod 600 /etc/server-pulse/config.env
```

## Required

| Env | Description |
|---|---|
| `TELEGRAM_BOT_TOKEN` | Bot token from BotFather. See [telegram-setup.md](telegram-setup.md). |
| `TELEGRAM_CHAT_ID` | Numeric chat ID (user, group, or channel). |

## Identity

| Env | Default | Description |
|---|---|---|
| `SERVER_NAME` | `$(hostname -s)` | Shown in every alert. Use a memorable name in a fleet (`web-01`, `db-prod`). |

## Outbound proxy (optional)

Use this when `api.telegram.org` is unreachable directly (RKN, corporate firewalls).

| Env | Description |
|---|---|
| `OUTBOUND_PROXY_URI` | e.g. `http://proxy.example.com:9999` |
| `OUTBOUND_PROXY_AUTH` | e.g. `username:password`; omit if proxy is open |

## Thresholds

| Env | Default |
|---|---|
| `DISK_WARN_PCT` | `85` |
| `DISK_CRIT_PCT` | `95` |
| `INODE_WARN_PCT` | `85` |
| `INODE_CRIT_PCT` | `95` |
| `RAM_WARN_PCT` | `85` |
| `RAM_CRIT_PCT` | `95` |
| `SWAP_WARN_PCT` | `50` |
| `SWAP_CRIT_PCT` | `80` |
| `LOAD_WARN_MULT` | `1.5` |
| `LOAD_CRIT_MULT` | `3.0` |
| `CPU_WARN_PCT` | `85` |
| `CPU_CRIT_PCT` | `95` |

## Check toggles

| Env | Default |
|---|---|
| `CHECK_DISK` | `true` |
| `CHECK_INODE` | `true` |
| `CHECK_MEMORY` | `true` |
| `CHECK_LOAD` | `true` |
| `CHECK_CPU` | `true` |
| `CHECK_OOM` | `true` |
| `CHECK_DOCKER` | `false` |
| `CHECK_SYSTEMD` | `false` |

## Allowlists

| Env | Description |
|---|---|
| `DOCKER_CONTAINERS` | Space-separated container names. Required when `CHECK_DOCKER=true`. |
| `SYSTEMD_UNITS` | Space-separated unit names. Required when `CHECK_SYSTEMD=true`. |
| `DISK_EXCLUDE_REGEX` | Bash regex matched against `df` mountpoints. Default excludes virtual/snap/docker filesystems. |

## Throttling

| Env | Default | Description |
|---|---|---|
| `WARN_THROTTLE_MIN` | `60` | Minimum minutes between repeated WARNING messages for the same check. |
| `CRIT_THROTTLE_MIN` | `30` | Same, for CRITICAL. |
| `RESOLVED_NOTIFY` | `true` | Send a one-shot RESOLVED message when a check returns to OK. |

## Tuning examples

### Stricter disk thresholds for a small VPS

```bash
DISK_WARN_PCT=75
DISK_CRIT_PCT=90
```

### Watch only specific filesystems

```bash
# Exclude everything except / and /data:
DISK_EXCLUDE_REGEX="^/(dev|proc|sys|run|snap|var|tmp|home|boot|opt|usr)"
```

### Quieter critical alerts

```bash
CRIT_THROTTLE_MIN=120   # repeat every 2 hours instead of every 30 min
```

### Watch your prod stack

```bash
CHECK_DOCKER=true
DOCKER_CONTAINERS="respawn-app respawn-postgres respawn-redis"

CHECK_SYSTEMD=true
SYSTEMD_UNITS="docker.service caddy.service"
```

## After editing

There's no daemon to reload — the next timer fire picks up the new values automatically. To verify the new config parses correctly:

```bash
sudo server-pulse test
```
