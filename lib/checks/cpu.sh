#!/usr/bin/env bash
# server-pulse check: instantaneous CPU usage over a 1-second sample of /proc/stat.

sp_check_cpu() {
    [[ "$CHECK_CPU" == "true" ]] || return 0

    local _ u1 n1 s1 i1 w1 q1 sq1 st1
    local u2 n2 s2 i2 w2 q2 sq2 st2

    # Two samples 1s apart. Default missing fields (older kernels) to 0.
    read -r _ u1 n1 s1 i1 w1 q1 sq1 st1 _ < /proc/stat
    : "${w1:=0}" "${q1:=0}" "${sq1:=0}" "${st1:=0}"
    sleep 1
    read -r _ u2 n2 s2 i2 w2 q2 sq2 st2 _ < /proc/stat
    : "${w2:=0}" "${q2:=0}" "${sq2:=0}" "${st2:=0}"

    local total1 total2 idle1 idle2 total_delta idle_delta used_pct status value
    total1=$(( u1 + n1 + s1 + i1 + w1 + q1 + sq1 + st1 ))
    total2=$(( u2 + n2 + s2 + i2 + w2 + q2 + sq2 + st2 ))
    idle1=$(( i1 + w1 ))
    idle2=$(( i2 + w2 ))

    total_delta=$(( total2 - total1 ))
    idle_delta=$(( idle2 - idle1 ))
    (( total_delta > 0 )) || return 0

    used_pct=$(( 100 * (total_delta - idle_delta) / total_delta ))
    (( used_pct < 0 )) && used_pct=0
    (( used_pct > 100 )) && used_pct=100

    status="OK"
    if (( used_pct >= CPU_CRIT_PCT )); then
        status="CRIT"
    elif (( used_pct >= CPU_WARN_PCT )); then
        status="WARN"
    fi

    value="${used_pct}%"
    sp_metric_record "cpu" "$used_pct"
    sp_state_dispatch "cpu" "$status" "$value" "CPU usage: ${value}"
}
