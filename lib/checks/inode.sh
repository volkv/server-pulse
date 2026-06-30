#!/usr/bin/env bash
# server-pulse check: inode usage per mountpoint.

sp_check_inode() {
    [[ "$CHECK_INODE" == "true" ]] || return 0

    local filesystem inodes iused ifree pct mount pct_num status value message
    while read -r filesystem inodes iused ifree pct mount; do
        [[ "$filesystem" == "Filesystem" ]] && continue
        [[ -z "$mount" ]] && continue
        [[ "$mount" =~ $DISK_EXCLUDE_REGEX ]] && continue
        # Some filesystems (e.g. btrfs subvolumes) report '-' for inode usage.
        [[ "$pct" == "-" ]] && continue

        pct_num="${pct%\%}"
        [[ "$pct_num" =~ ^[0-9]+$ ]] || continue

        status="OK"
        if (( pct_num >= INODE_CRIT_PCT )); then
            status="CRIT"
        elif (( pct_num >= INODE_WARN_PCT )); then
            status="WARN"
        fi

        value="${pct_num}% on ${mount} (free: ${ifree} / ${inodes})"
        message="Inode usage: ${value}"
        sp_metric_record "inode:${mount}" "$pct_num"
        sp_state_dispatch "inode:${mount}" "$status" "$value" "$message"
    done < <(df -iP -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null)

    # shellcheck disable=SC2034
    : "$iused"
}
