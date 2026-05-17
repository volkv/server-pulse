#!/usr/bin/env bash
# server-pulse: Telegram Bot API notifier.
#
# Honours an optional outbound HTTP/HTTPS proxy (OUTBOUND_PROXY_URI,
# OUTBOUND_PROXY_AUTH) for environments where api.telegram.org is blocked.

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

sp_telegram_send() {
    local text="$1"
    local url="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"

    local curl_args=(
        -sS
        --max-time 15
        --retry 2
        --retry-delay 2
        --write-out '\nHTTPSTATUS:%{http_code}'
        --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}"
        --data-urlencode "text=${text}"
        --data-urlencode "disable_web_page_preview=true"
    )

    if [[ -n "${OUTBOUND_PROXY_URI:-}" ]]; then
        curl_args+=(-x "$OUTBOUND_PROXY_URI")
        if [[ -n "${OUTBOUND_PROXY_AUTH:-}" ]]; then
            curl_args+=(-U "$OUTBOUND_PROXY_AUTH")
        fi
    fi

    curl_args+=("$url")

    local response http_code
    if ! response="$(curl "${curl_args[@]}" 2>&1)"; then
        sp_log_error "Telegram curl failed: $response"
        return 1
    fi

    http_code="${response##*HTTPSTATUS:}"
    response="${response%$'\n'HTTPSTATUS:*}"

    if [[ "$http_code" != "200" ]]; then
        sp_log_error "Telegram API HTTP $http_code: $response"
        return 1
    fi
    return 0
}
