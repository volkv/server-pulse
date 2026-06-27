#!/usr/bin/env bash
# server-pulse: Mission Control sink.
#
# Mirrors every alert that reaches a human (WARN / CRIT / RESOLVED) into the
# Mission Control fleet timeline via POST /api/ingest/server. Optional and
# fail-safe: a no-op unless both MC_URL and MC_TOKEN are configured, and a
# failed POST never aborts the monitoring run (the caller ignores the result).
#
# The bearer token is kept out of the curl command line — like the Telegram
# notifier, it goes into a 0600 tempfile read via `curl --config`, so other
# local users can't read it from /proc/<pid>/cmdline. The JSON payload is not
# a secret and is passed on the command line.
#
# MC attributes the event to a project by matching `host` against projects.host
# in the registry, so no slug is sent — SERVER_NAME is the host identity.

# Escape a string for embedding inside a JSON double-quoted value. Covers the
# characters that actually occur in alert text (no jq dependency — this repo is
# pure bash). Backslash must be replaced first.
_sp_json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

# sp_mc_report <severity> <check_id> <message>
#   severity — WARN | CRIT | RESOLVED (anything else maps to "info")
#   check_id — the dispatch id, e.g. "disk:/", "memory:ram", "docker:app"
#   message — full alert text
# Returns 0 on success (or when not configured), 1 on delivery failure.
sp_mc_report() {
    local severity_raw="$1" check="$2" message="$3"

    # Optional sink — silently no-op unless fully configured.
    [[ -n "${MC_URL:-}" && -n "${MC_TOKEN:-}" ]] || return 0

    # Map server-pulse severity to the ingest enum (critical|warning|resolved|info).
    local severity
    case "$severity_raw" in
        CRIT)     severity="critical" ;;
        WARN)     severity="warning"  ;;
        RESOLVED) severity="resolved" ;;
        *)        severity="info"     ;;
    esac

    local host_j check_j message_j
    host_j="$(_sp_json_escape "$SERVER_NAME")"
    check_j="$(_sp_json_escape "$check")"
    message_j="$(_sp_json_escape "$message")"

    local payload
    payload="$(printf '{"host":"%s","severity":"%s","check":"%s","message":"%s"}' \
        "$host_j" "$severity" "$check_j" "$message_j")"

    local base cfg
    base="${MC_URL%/}"
    cfg="$(umask 077; mktemp -t server-pulse.mc.curlrc.XXXXXX)"
    {
        printf 'url = "%s/api/ingest/server"\n' "$(_sp_cfg_escape "$base")"
        printf 'header = "Authorization: Bearer %s"\n' "$(_sp_cfg_escape "$MC_TOKEN")"
        printf 'header = "Content-Type: application/json"\n'
        printf 'silent\n'
        printf 'show-error\n'
        printf 'max-time = 10\n'
        printf 'write-out = "\\nHTTPSTATUS:%%{http_code}"\n'
    } > "$cfg"

    local response="" rc=0
    response="$(curl --config "$cfg" --data "$payload" 2>&1)" || rc=$?
    rm -f "$cfg"

    if (( rc != 0 )); then
        sp_log_warn "Mission Control report failed (rc=${rc}): ${response}"
        return 1
    fi

    local http_code
    http_code="${response##*HTTPSTATUS:}"
    if [[ "$http_code" != "200" ]]; then
        sp_log_warn "Mission Control API HTTP ${http_code}: ${response%$'\n'HTTPSTATUS:*}"
        return 1
    fi
    return 0
}
