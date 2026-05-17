#!/usr/bin/env bash
# server-pulse: Telegram Bot API notifier.
#
# Secrets (bot token in URL, proxy credentials) are kept out of the curl
# command line — other local users would otherwise be able to read them via
# /proc/<pid>/cmdline or `ps`. The token and proxy creds go into a 0600
# tempfile that curl reads with --config, then we remove it.
#
# Non-secret args (chat_id, text) are passed on the command line; they show
# up in `ps` but are not credentials.

sp_notify() {
    local severity="$1"   # WARN | CRIT | RESOLVED
    local message="$2"

    if sp_silence_active; then
        sp_log_info "Silenced — suppressing $severity notification"
        return 0
    fi

    local emoji prefix
    case "$severity" in
        CRIT)     emoji="🚨"; prefix="CRITICAL" ;;
        WARN)     emoji="⚠️";  prefix="WARNING"  ;;
        RESOLVED) emoji="✅"; prefix="RESOLVED" ;;
        *)        emoji="ℹ️";  prefix="$severity" ;;
    esac

    local text
    text="$(printf '%s %s · %s\n%s' "$emoji" "$prefix" "$SERVER_NAME" "$message")"

    sp_telegram_send "$text"
}

# Escape a string for use inside a curl-config double-quoted value:
# backslash and double-quote must be backslash-escaped.
_sp_cfg_escape() {
    local v="$1"
    v="${v//\\/\\\\}"
    v="${v//\"/\\\"}"
    printf '%s' "$v"
}

sp_telegram_send() {
    local text="$1"

    local cfg token_esc proxy_uri_esc proxy_auth_esc
    cfg="$(umask 077; mktemp -t server-pulse.curlrc.XXXXXX)"

    token_esc="$(_sp_cfg_escape "$TELEGRAM_BOT_TOKEN")"
    {
        printf 'url = "https://api.telegram.org/bot%s/sendMessage"\n' "$token_esc"
        if [[ -n "${OUTBOUND_PROXY_URI:-}" ]]; then
            proxy_uri_esc="$(_sp_cfg_escape "$OUTBOUND_PROXY_URI")"
            printf 'proxy = "%s"\n' "$proxy_uri_esc"
            if [[ -n "${OUTBOUND_PROXY_AUTH:-}" ]]; then
                proxy_auth_esc="$(_sp_cfg_escape "$OUTBOUND_PROXY_AUTH")"
                printf 'proxy-user = "%s"\n' "$proxy_auth_esc"
            fi
        fi
        printf 'silent\n'
        printf 'show-error\n'
        printf 'max-time = 15\n'
        printf 'retry = 2\n'
        printf 'retry-delay = 2\n'
        printf 'write-out = "\\nHTTPSTATUS:%%{http_code}"\n'
    } > "$cfg"

    local response="" rc=0
    response="$(
        curl --config "$cfg" \
            --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
            --data-urlencode "text=${text}" \
            --data-urlencode "disable_web_page_preview=true" \
            2>&1
    )" || rc=$?

    rm -f "$cfg"

    if (( rc != 0 )); then
        sp_log_error "Telegram curl failed (rc=${rc}): ${response}"
        return 1
    fi

    local http_code body
    http_code="${response##*HTTPSTATUS:}"
    body="${response%$'\n'HTTPSTATUS:*}"

    if [[ "$http_code" != "200" ]]; then
        sp_log_error "Telegram API HTTP ${http_code}: ${body}"
        return 1
    fi
    return 0
}
