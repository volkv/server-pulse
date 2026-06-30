#!/usr/bin/env bash
# server-pulse check: RAM and swap usage from /proc/meminfo.

sp_check_memory() {
    [[ "$CHECK_MEMORY" == "true" ]] || return 0
    _sp_check_ram
    _sp_check_swap
}

_sp_check_ram() {
    local mem_total mem_avail
    mem_total="$(awk '/^MemTotal:/ {print $2; exit}' /proc/meminfo)"
    mem_avail="$(awk '/^MemAvailable:/ {print $2; exit}' /proc/meminfo)"
    [[ -n "$mem_total" && -n "$mem_avail" ]] || return 0
    (( mem_total > 0 )) || return 0

    local used_pct used_mb total_mb status value
    used_pct=$(( 100 - (mem_avail * 100 / mem_total) ))
    (( used_pct < 0 )) && used_pct=0

    status="OK"
    if (( used_pct >= RAM_CRIT_PCT )); then
        status="CRIT"
    elif (( used_pct >= RAM_WARN_PCT )); then
        status="WARN"
    fi

    used_mb=$(( (mem_total - mem_avail) / 1024 ))
    total_mb=$(( mem_total / 1024 ))
    value="${used_pct}% (${used_mb} MB / ${total_mb} MB)"
    sp_metric_record "ram" "$used_pct"
    sp_state_dispatch "memory:ram" "$status" "$value" "RAM usage: ${value}"
}

_sp_check_swap() {
    local swap_total swap_free
    swap_total="$(awk '/^SwapTotal:/ {print $2; exit}' /proc/meminfo)"
    swap_free="$(awk '/^SwapFree:/ {print $2; exit}' /proc/meminfo)"
    [[ -n "$swap_total" && -n "$swap_free" ]] || return 0
    (( swap_total > 0 )) || return 0

    local used_pct used_mb total_mb status value
    used_pct=$(( 100 - (swap_free * 100 / swap_total) ))
    (( used_pct < 0 )) && used_pct=0

    status="OK"
    if (( used_pct >= SWAP_CRIT_PCT )); then
        status="CRIT"
    elif (( used_pct >= SWAP_WARN_PCT )); then
        status="WARN"
    fi

    used_mb=$(( (swap_total - swap_free) / 1024 ))
    total_mb=$(( swap_total / 1024 ))
    value="${used_pct}% (${used_mb} MB / ${total_mb} MB)"
    sp_metric_record "swap" "$used_pct"
    sp_state_dispatch "memory:swap" "$status" "$value" "Swap usage: ${value}"
}
