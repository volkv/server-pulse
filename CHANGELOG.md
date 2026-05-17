# Changelog

All notable changes to **server-pulse** are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [SemVer](https://semver.org/).

## [Unreleased]

## [1.0.0] - 2026-05-17

### Added
- Initial public release.
- Checks: disk, inode, memory (RAM + swap), load average, CPU, OOM-killer, Docker containers, systemd units.
- Telegram notifications via Bot API.
- Optional outbound HTTP/HTTPS proxy for Telegram API (`OUTBOUND_PROXY_URI`, `OUTBOUND_PROXY_AUTH`).
- State-based alert throttling with WARN/CRIT/RESOLVED transitions and WARN→CRIT instant escalation.
- OOM dedup via SHA-1 hash of matched journal lines.
- CLI commands: `run`, `test`, `status`, `silence <duration>`, `unsilence`, `version`.
- systemd timer (5 min interval with 30 s randomized delay).
- `install.sh` with prerequisite checks, secure config permissions (chmod 600), symlink to `/usr/local/bin`.
- shellcheck CI workflow.
