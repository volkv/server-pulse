#!/usr/bin/env bash
# server-pulse check: OOM killer events.
#
# Strategy: scan the kernel journal for the last 15 minutes (3× default timer
# interval) and look for OOM markers. Dedup by SHA-1 of the matched line so
# the same event is not reported repeatedly. The seen-hash file is trimmed to
# the last 200 lines to avoid unbounded growth.

sp_check_oom() {
    [[ "$CHECK_OOM" == "true" ]] || return 0
    command -v journalctl >/dev/null 2>&1 || return 0

    local seen_file="${SP_STATE_DIR}/oom.seen"
    local oom_lines
    oom_lines="$(
        journalctl -k --since='15 minutes ago' --no-pager --output=short-iso 2>/dev/null \
        | grep -iE 'killed process|out of memory|invoked oom-killer' || true
    )"

    if [[ -z "$oom_lines" ]]; then
        sp_state_dispatch "oom" "OK" "no events" "OOM killer: clear"
        return 0
    fi

    local line hash new_lines=""
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        hash="$(printf '%s' "$line" | sha1sum | cut -d' ' -f1)"
        if ! grep -qxF "$hash" "$seen_file" 2>/dev/null; then
            printf '%s\n' "$hash" >> "$seen_file"
            new_lines+="${line}"$'\n'
        fi
    done <<< "$oom_lines"

    if [[ -f "$seen_file" ]]; then
        local tmp="${seen_file}.tmp"
        tail -n 200 "$seen_file" > "$tmp" && mv -f "$tmp" "$seen_file"
    fi

    [[ -z "$new_lines" ]] && return 0

    local count sample value message
    count="$(printf '%s' "$new_lines" | grep -c .)"
    sample="$(printf '%s' "$new_lines" | head -n 3)"
    value="${count} new event(s)"
    message="$(printf 'OOM killer triggered (%d new events):\n%s' "$count" "$sample")"
    sp_state_dispatch "oom" "CRIT" "$value" "$message"
}
