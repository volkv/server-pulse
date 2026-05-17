#!/usr/bin/env bash
# server-pulse check: systemd units from an allowlist must be active.

sp_check_systemd() {
    [[ "$CHECK_SYSTEMD" == "true" ]] || return 0
    command -v systemctl >/dev/null 2>&1 || return 0

    local unit state status message
    for unit in $SYSTEMD_UNITS; do
        state="$(systemctl is-active "$unit" 2>/dev/null || true)"
        [[ -z "$state" ]] && state="unknown"

        if [[ "$state" == "active" ]]; then
            status="OK"
        else
            status="CRIT"
        fi

        message="systemd unit \"${unit}\": ${state}"
        sp_state_dispatch "systemd:${unit}" "$status" "$state" "$message"
    done
}
