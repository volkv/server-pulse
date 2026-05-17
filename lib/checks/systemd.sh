#!/usr/bin/env bash
# server-pulse check: systemd units from an allowlist must be active.
#
# If `systemctl` is unavailable while CHECK_SYSTEMD=true, that is itself a
# CRITICAL self-check failure — silently skipping would hide problems.

sp_check_systemd() {
    [[ "$CHECK_SYSTEMD" == "true" ]] || return 0

    if ! command -v systemctl >/dev/null 2>&1; then
        sp_state_dispatch "systemd:_runtime" "CRIT" "systemctl missing" \
            "CHECK_SYSTEMD=true but 'systemctl' is not on PATH — units cannot be verified"
        return 0
    fi
    sp_state_dispatch "systemd:_runtime" "OK" "systemctl present" "systemd available"

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
