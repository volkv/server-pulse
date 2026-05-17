#!/usr/bin/env bash
# server-pulse check: 5-minute load average normalized by logical CPU count.

sp_check_load() {
    [[ "$CHECK_LOAD" == "true" ]] || return 0

    local load5 cores status mult value
    load5="$(awk '{print $2}' /proc/loadavg)"
    cores="$(nproc 2>/dev/null || echo 1)"
    (( cores < 1 )) && cores=1

    # bash lacks float math; awk handles ratio comparison.
    status="$(awk -v l="$load5" -v c="$cores" -v w="$LOAD_WARN_MULT" -v cr="$LOAD_CRIT_MULT" '
        BEGIN {
            r = l / c
            if      (r >= cr) print "CRIT"
            else if (r >= w)  print "WARN"
            else               print "OK"
        }')"

    mult="$(awk -v l="$load5" -v c="$cores" 'BEGIN { printf "%.2f", l/c }')"
    value="${load5} (5min) on ${cores} cores  →  ${mult}x"

    sp_state_dispatch "load" "$status" "$value" "Load average: ${value}"
}
