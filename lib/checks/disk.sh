#!/usr/bin/env bash
# server-pulse check: disk usage per mountpoint.

sp_check_disk() {
    [[ "$CHECK_DISK" == "true" ]] || return 0

    local filesystem size used avail pct mount pct_num status value message
    while read -r filesystem size used avail pct mount; do
        [[ "$filesystem" == "Filesystem" ]] && continue
        [[ -z "$mount" ]] && continue
        [[ "$mount" =~ $DISK_EXCLUDE_REGEX ]] && continue

        pct_num="${pct%\%}"
        [[ "$pct_num" =~ ^[0-9]+$ ]] || continue

        status="OK"
        if (( pct_num >= DISK_CRIT_PCT )); then
            status="CRIT"
        elif (( pct_num >= DISK_WARN_PCT )); then
            status="WARN"
        fi

        value="${pct_num}% on ${mount} (free: ${avail} / ${size})"
        message="Disk usage: ${value}"
        sp_state_dispatch "disk:${mount}" "$status" "$value" "$message"
    done < <(df -hP -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null)

    # shellcheck disable=SC2034
    : "$used"
}
