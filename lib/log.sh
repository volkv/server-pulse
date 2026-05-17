#!/usr/bin/env bash
# server-pulse: logging helpers. Writes to stderr; when run under systemd
# the stream is captured by journald automatically.

sp_log() {
    local level="$1"
    shift
    local ts
    ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    printf '[%s] %s %s\n' "$ts" "$level" "$*" >&2
}

sp_log_info()  { sp_log "INFO"  "$@"; }
sp_log_warn()  { sp_log "WARN"  "$@"; }
sp_log_error() { sp_log "ERROR" "$@"; }

sp_log_debug() {
    [[ "${SP_DEBUG:-false}" == "true" ]] && sp_log "DEBUG" "$@"
    return 0
}
