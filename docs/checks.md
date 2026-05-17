# Linux server health checks reference — server-pulse

Every check has an on/off toggle, threshold envs, and a state key used for alert tracking. All envs live in `/etc/server-pulse/config.env`.

## disk

Reports usage per mountpoint via `df -hP`. `tmpfs`, `devtmpfs`, `squashfs`, and `overlay` filesystems are excluded by default. Add your own exclusions with `DISK_EXCLUDE_REGEX`.

| Env | Default |
|---|---|
| `CHECK_DISK` | `true` |
| `DISK_WARN_PCT` | `85` |
| `DISK_CRIT_PCT` | `95` |
| `DISK_EXCLUDE_REGEX` | `^/(dev\|proc\|sys\|run\|snap\|var/lib/docker)` |

State key: `disk:<mountpoint>` (e.g. `disk:/`, `disk:/var`).

## inode

Same as `disk`, but for inode usage (`df -iP`). Filesystems that don't report inode counts (e.g. some btrfs configurations) are skipped.

| Env | Default |
|---|---|
| `CHECK_INODE` | `true` |
| `INODE_WARN_PCT` | `85` |
| `INODE_CRIT_PCT` | `95` |

State key: `inode:<mountpoint>`.

## memory (RAM + swap)

RAM is measured against `MemAvailable` from `/proc/meminfo` — this is the kernel's own estimate of "memory available for new allocations without swapping", which is far more meaningful than "free". Swap is measured against `SwapTotal` / `SwapFree`.

| Env | Default |
|---|---|
| `CHECK_MEMORY` | `true` |
| `RAM_WARN_PCT` | `85` |
| `RAM_CRIT_PCT` | `95` |
| `SWAP_WARN_PCT` | `50` |
| `SWAP_CRIT_PCT` | `80` |

State keys: `memory:ram`, `memory:swap`.

## load

5-minute load average from `/proc/loadavg`, divided by `nproc`. A 4-core box at load `6.0` is reported as `1.5×`.

| Env | Default |
|---|---|
| `CHECK_LOAD` | `true` |
| `LOAD_WARN_MULT` | `1.5` |
| `LOAD_CRIT_MULT` | `3.0` |

State key: `load`.

## cpu

Reads `/proc/stat`, sleeps 1 second, reads again, and reports the percentage of non-idle CPU time during that interval. Steal time (relevant on virtualized hosts) is included in the "non-idle" bucket — a noisy neighbour will be visible.

| Env | Default |
|---|---|
| `CHECK_CPU` | `true` |
| `CPU_WARN_PCT` | `85` |
| `CPU_CRIT_PCT` | `95` |

State key: `cpu`.

## oom

Scans `journalctl -k --since='15 minutes ago'` for these patterns:

- `Out of memory`
- `Killed process`
- `invoked oom-killer`

Each matched line is hashed (SHA-1). New hashes trigger a CRITICAL alert; previously seen ones are skipped. The seen-hash file is trimmed to the last 200 entries to bound disk usage.

| Env | Default |
|---|---|
| `CHECK_OOM` | `true` |

State key: `oom`. Requires `journalctl` to be available.

## docker

Allowlist of containers that **must** be in the `running` state. Anything else (`exited`, `restarting`, `missing`, ...) yields a CRITICAL.

| Env | Default |
|---|---|
| `CHECK_DOCKER` | `false` |
| `DOCKER_CONTAINERS` | `""` (required if `CHECK_DOCKER=true`) |

State key: `docker:<container_name>`.

Why allowlist instead of "watch everything"? Because the only containers worth alerting on are the ones you've decided are critical. A debug or migration container that exited last week is not an alert.

## systemd

Allowlist of systemd units that must be `active`. Useful for cron-jobs, agents, custom daemons that aren't containerized.

| Env | Default |
|---|---|
| `CHECK_SYSTEMD` | `false` |
| `SYSTEMD_UNITS` | `""` (required if `CHECK_SYSTEMD=true`) |

State key: `systemd:<unit_name>`.

---

## Alert lifecycle

```
       ┌─────► WARN ──────┐
       │         │        │
       OK        ▼        ▼
       ▲       CRIT ───► RESOLVED ──► OK
       └─────────┘
```

- `OK → WARN` or `OK → CRIT`: first alert is sent immediately.
- `WARN → CRIT`: **escalation** is sent immediately, no throttle.
- `WARN → WARN`: re-sent after `WARN_THROTTLE_MIN` minutes (default 60).
- `CRIT → CRIT`: re-sent after `CRIT_THROTTLE_MIN` minutes (default 30).
- `CRIT → WARN`: state stays `CRIT` (no de-escalation noise) until it returns to `OK`.
- `WARN → OK` or `CRIT → OK`: a single `RESOLVED` is sent (disable via `RESOLVED_NOTIFY=false`).

While a `silence` is active, transitions still update the state file but notifications are suppressed.
