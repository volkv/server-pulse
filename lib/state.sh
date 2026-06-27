#!/usr/bin/env bash
# server-pulse: per-check alert state, transitions, throttling, and silence.
#
# State files live under $SP_STATE_DIR/state/<sanitized-id>.state with KV format:
#   id=<original check key>
#   status=OK|WARN|CRIT
#   last_sent=<epoch>
#   value=<human description>
#
# A check key identifies a single alertable entity, e.g. "disk:/", "memory:ram",
# "docker:respawn-app". Anything not matching [a-zA-Z0-9_-] is replaced with '_'
# when generating the filename; the original id is stored inside the file so
# `status` can display it verbatim.

sp_state_path() {
    local id="$1"
    local safe="${id//[^a-zA-Z0-9_-]/_}"
    printf '%s/state/%s.state' "$SP_STATE_DIR" "$safe"
}

sp_state_read() {
    # Reads status & last_sent from a state file into out-params. Returns OK,0
    # when the file is missing. Internal vars are prefixed to avoid shadowing
    # caller-provided out-param names.
    local _spsr_file="$1"
    local _spsr_status_var="$2"
    local _spsr_sent_var="$3"

    local _spsr_status="OK"
    local _spsr_sent=0

    if [[ -f "$_spsr_file" ]]; then
        local _spsr_key _spsr_val
        while IFS='=' read -r _spsr_key _spsr_val; do
            case "$_spsr_key" in
                status)    _spsr_status="$_spsr_val" ;;
                last_sent) _spsr_sent="$_spsr_val" ;;
            esac
        done < "$_spsr_file"
    fi

    printf -v "$_spsr_status_var" '%s' "$_spsr_status"
    printf -v "$_spsr_sent_var"   '%s' "$_spsr_sent"
}

sp_state_write() {
    local file="$1" status="$2" sent="$3" value="$4" id="$5"
    local tmp="${file}.tmp"
    {
        printf 'id=%s\n' "$id"
        printf 'status=%s\n' "$status"
        printf 'last_sent=%s\n' "$sent"
        printf 'value=%s\n' "$value"
    } > "$tmp"
    mv -f "$tmp" "$file"
}

sp_silence_active() {
    local file="$SP_STATE_DIR/silence"
    [[ -f "$file" ]] || return 1
    local until
    until="$(cat "$file" 2>/dev/null || echo 0)"
    [[ "$until" =~ ^[0-9]+$ ]] || return 1
    local now
    now="$(date +%s)"
    (( now < until ))
}

# Send a notification but never propagate failure to the caller — Telegram
# being temporarily unreachable must not abort the rest of the monitoring
# run. Returns 0 on success, 1 on send failure. The return code is consumed
# by sp_state_dispatch to decide whether to advance the throttle clock.
_sp_state_notify() {
    local severity="$1" message="$2" check="${3:-}"
    # Mission Control sink — mirrors the same notify decisions (so it inherits
    # throttling) but runs independent of Telegram silence, and fire-and-forget:
    # its result never gates Telegram delivery or the throttle clock below.
    sp_mc_report "$severity" "$check" "$message" || true
    if sp_notify "$severity" "$message"; then
        return 0
    fi
    sp_log_warn "Notification delivery failed (severity=$severity); will retry on next run"
    return 1
}

# Dispatch a check result.
#   $1 — check id (e.g. "disk:/")
#   $2 — new status: OK | WARN | CRIT
#   $3 — short value string (kept in state for `status` command)
#   $4 — full alert message body
sp_state_dispatch() {
    local id="$1" new="$2" value="$3" message="$4"
    local file
    file="$(sp_state_path "$id")"

    local prev last_sent
    sp_state_read "$file" prev last_sent

    local now
    now="$(date +%s)"

    case "$prev:$new" in
        OK:OK)
            return 0
            ;;
        OK:WARN|OK:CRIT|WARN:CRIT)
            # New alert or escalation — send immediately. Advance the
            # throttle clock only on successful delivery so a failed send
            # is retried next cycle without losing context.
            if _sp_state_notify "$new" "$message" "$id"; then
                sp_state_write "$file" "$new" "$now" "$value" "$id"
            else
                sp_state_write "$file" "$new" 0 "$value" "$id"
            fi
            ;;
        WARN:WARN)
            local throttle=$(( WARN_THROTTLE_MIN * 60 ))
            if (( now - last_sent >= throttle )); then
                if _sp_state_notify "$new" "$message" "$id"; then
                    sp_state_write "$file" "$new" "$now" "$value" "$id"
                else
                    sp_state_write "$file" "$new" "$last_sent" "$value" "$id"
                fi
            else
                sp_state_write "$file" "$new" "$last_sent" "$value" "$id"
            fi
            ;;
        CRIT:CRIT)
            local throttle=$(( CRIT_THROTTLE_MIN * 60 ))
            if (( now - last_sent >= throttle )); then
                if _sp_state_notify "$new" "$message" "$id"; then
                    sp_state_write "$file" "$new" "$now" "$value" "$id"
                else
                    sp_state_write "$file" "$new" "$last_sent" "$value" "$id"
                fi
            else
                sp_state_write "$file" "$new" "$last_sent" "$value" "$id"
            fi
            ;;
        CRIT:WARN)
            # Partial recovery: transition to WARN without a de-escalation
            # message. The retained last_sent makes WARN_THROTTLE_MIN govern
            # any future WARN reminders.
            sp_state_write "$file" "$new" "$last_sent" "$value" "$id"
            ;;
        WARN:OK|CRIT:OK)
            if [[ "$RESOLVED_NOTIFY" == "true" ]]; then
                # Best-effort: clearing state is more important than the
                # RESOLVED message, otherwise a single failed send would
                # leave the check stuck in WARN/CRIT forever.
                _sp_state_notify "RESOLVED" "$message" "$id" || true
            fi
            rm -f "$file"
            ;;
    esac
}
