#!/usr/bin/env bash
# server-pulse: Mission Control numeric metrics sink.
#
# Separate from sp_mc_report (threshold alerts → fleet timeline events): this ships the raw
# numeric value stream — cpu/ram/swap/load/disk/inode — to MC every run, powering the VPS
# tiles and load sparklines on the dashboard. Checks accumulate values via sp_metric_record
# during the run; sp_mc_metrics_flush sends the whole batch once at the end.
#
# Optional and fail-safe: a no-op unless both MC_URL and MC_TOKEN are configured (same pair as
# sp_mc_report), and a failed POST never aborts the run. Reuses _sp_json_escape / _sp_cfg_escape
# and the 0600-curlrc token-handling pattern from the Telegram / MC-report sinks.

# Accumulator — parallel arrays, appended to by sp_metric_record during a single run process.
SP_METRIC_KEYS=()
SP_METRIC_VALUES=()

# sp_metric_record <key> <value>
#   key   — canonical metric id: cpu | ram | swap | load | disk:<mount> | inode:<mount>
#   value — a number (% 0..100, or the load multiplier). Non-numeric input (a failed probe)
#           is silently dropped so the batch never carries garbage.
sp_metric_record() {
    local key="$1" value="$2"
    [[ "$value" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] || return 0
    SP_METRIC_KEYS+=("$key")
    SP_METRIC_VALUES+=("$value")
}

# Ship the accumulated metrics as one POST /api/ingest/host-metrics. No-op unless configured
# and unless something was recorded. Returns 0 on success/no-op, 1 on delivery failure.
sp_mc_metrics_flush() {
    [[ -n "${MC_URL:-}" && -n "${MC_TOKEN:-}" ]] || return 0
    (( ${#SP_METRIC_KEYS[@]} > 0 )) || return 0

    local host_j items="" i key_j
    host_j="$(_sp_json_escape "$SERVER_NAME")"
    for i in "${!SP_METRIC_KEYS[@]}"; do
        key_j="$(_sp_json_escape "${SP_METRIC_KEYS[$i]}")"
        [[ -n "$items" ]] && items+=","
        items+="$(printf '{"key":"%s","value":%s}' "$key_j" "${SP_METRIC_VALUES[$i]}")"
    done

    local payload
    payload="$(printf '{"host":"%s","metrics":[%s]}' "$host_j" "$items")"

    local base cfg
    base="${MC_URL%/}"
    cfg="$(umask 077; mktemp -t server-pulse.mcm.curlrc.XXXXXX)"
    {
        printf 'url = "%s/api/ingest/host-metrics"\n' "$(_sp_cfg_escape "$base")"
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
        sp_log_warn "Mission Control metrics flush failed (rc=${rc}): ${response}"
        return 1
    fi

    local http_code
    http_code="${response##*HTTPSTATUS:}"
    if [[ "$http_code" != "200" ]]; then
        sp_log_warn "Mission Control metrics API HTTP ${http_code}"
        return 1
    fi
    return 0
}
