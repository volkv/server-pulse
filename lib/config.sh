#!/usr/bin/env bash
# server-pulse: configuration loading, defaults, and validation.

SP_CONFIG_PATH="${SP_CONFIG_PATH:-/etc/server-pulse/config.env}"
SP_STATE_DIR="${SP_STATE_DIR:-/var/lib/server-pulse}"

sp_config_load() {
    if [[ ! -e "$SP_CONFIG_PATH" ]]; then
        sp_log_error "Config file not found: $SP_CONFIG_PATH"
        sp_log_error "Copy config/config.example.env and edit it before running."
        return 1
    fi

    # The config is sourced as the calling user. Refuse to run if it could
    # have been tampered with — must be a regular file (not a symlink),
    # owned by the effective UID, and not group/world writable.
    if [[ -L "$SP_CONFIG_PATH" ]]; then
        sp_log_error "Config path is a symlink — refusing to source: $SP_CONFIG_PATH"
        return 1
    fi
    if [[ ! -f "$SP_CONFIG_PATH" ]]; then
        sp_log_error "Config path is not a regular file: $SP_CONFIG_PATH"
        return 1
    fi

    local file_uid file_mode
    file_uid="$(stat -c '%u' "$SP_CONFIG_PATH")"
    file_mode="$(stat -c '%a' "$SP_CONFIG_PATH")"

    if [[ "$file_uid" != "$EUID" ]]; then
        sp_log_error "Config $SP_CONFIG_PATH is owned by uid $file_uid; refusing to source as uid $EUID"
        sp_log_error "Run: sudo chown $(id -un): $SP_CONFIG_PATH"
        return 1
    fi

    case "$file_mode" in
        400|440|600|640) ;;
        *)
            sp_log_error "Insecure permissions on $SP_CONFIG_PATH: $file_mode (expected 600 or 640)"
            sp_log_error "Run: sudo chmod 600 $SP_CONFIG_PATH"
            return 1
            ;;
    esac

    # shellcheck source=/dev/null
    source "$SP_CONFIG_PATH"

    sp_config_apply_defaults
    sp_config_validate || return 1

    mkdir -p "$SP_STATE_DIR/state"
    chmod 700 "$SP_STATE_DIR" 2>/dev/null || true
}

sp_config_apply_defaults() {
    : "${SERVER_NAME:=$(hostname -s)}"

    : "${DISK_WARN_PCT:=85}"
    : "${DISK_CRIT_PCT:=95}"
    : "${INODE_WARN_PCT:=85}"
    : "${INODE_CRIT_PCT:=95}"
    : "${RAM_WARN_PCT:=85}"
    : "${RAM_CRIT_PCT:=95}"
    : "${SWAP_WARN_PCT:=50}"
    : "${SWAP_CRIT_PCT:=80}"
    : "${LOAD_WARN_MULT:=1.5}"
    : "${LOAD_CRIT_MULT:=3.0}"
    : "${CPU_WARN_PCT:=85}"
    : "${CPU_CRIT_PCT:=95}"

    : "${CHECK_DISK:=true}"
    : "${CHECK_INODE:=true}"
    : "${CHECK_MEMORY:=true}"
    : "${CHECK_LOAD:=true}"
    : "${CHECK_CPU:=true}"
    : "${CHECK_OOM:=true}"
    : "${CHECK_DOCKER:=false}"
    : "${CHECK_SYSTEMD:=false}"

    : "${DOCKER_CONTAINERS:=}"
    : "${SYSTEMD_UNITS:=}"
    : "${DISK_EXCLUDE_REGEX:=^/(dev|proc|sys|run|snap|var/lib/docker)}"

    : "${WARN_THROTTLE_MIN:=60}"
    : "${CRIT_THROTTLE_MIN:=30}"
    : "${RESOLVED_NOTIFY:=true}"

    : "${OUTBOUND_PROXY_URI:=}"
    : "${OUTBOUND_PROXY_AUTH:=}"

    export SERVER_NAME \
        DISK_WARN_PCT DISK_CRIT_PCT INODE_WARN_PCT INODE_CRIT_PCT \
        RAM_WARN_PCT RAM_CRIT_PCT SWAP_WARN_PCT SWAP_CRIT_PCT \
        LOAD_WARN_MULT LOAD_CRIT_MULT CPU_WARN_PCT CPU_CRIT_PCT \
        CHECK_DISK CHECK_INODE CHECK_MEMORY CHECK_LOAD CHECK_CPU CHECK_OOM \
        CHECK_DOCKER CHECK_SYSTEMD DOCKER_CONTAINERS SYSTEMD_UNITS \
        DISK_EXCLUDE_REGEX WARN_THROTTLE_MIN CRIT_THROTTLE_MIN RESOLVED_NOTIFY \
        OUTBOUND_PROXY_URI OUTBOUND_PROXY_AUTH
}

_sp_require_int() {
    local name="$1"
    local val="${!name:-}"
    if ! [[ "$val" =~ ^[0-9]+$ ]]; then
        sp_log_error "$name must be a non-negative integer (got: \"$val\")"
        return 1
    fi
}

_sp_require_num() {
    # Non-negative number with optional decimal part.
    local name="$1"
    local val="${!name:-}"
    if ! [[ "$val" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        sp_log_error "$name must be a non-negative number (got: \"$val\")"
        return 1
    fi
}

sp_config_validate() {
    local ok=true

    if [[ -z "${TELEGRAM_BOT_TOKEN:-}" ]]; then
        sp_log_error "TELEGRAM_BOT_TOKEN is not set"
        ok=false
    fi
    if [[ -z "${TELEGRAM_CHAT_ID:-}" ]]; then
        sp_log_error "TELEGRAM_CHAT_ID is not set"
        ok=false
    fi
    if [[ "$CHECK_DOCKER" == "true" && -z "$DOCKER_CONTAINERS" ]]; then
        sp_log_error "CHECK_DOCKER=true but DOCKER_CONTAINERS is empty"
        ok=false
    fi
    if [[ "$CHECK_SYSTEMD" == "true" && -z "$SYSTEMD_UNITS" ]]; then
        sp_log_error "CHECK_SYSTEMD=true but SYSTEMD_UNITS is empty"
        ok=false
    fi

    local var
    for var in DISK_WARN_PCT DISK_CRIT_PCT \
               INODE_WARN_PCT INODE_CRIT_PCT \
               RAM_WARN_PCT RAM_CRIT_PCT \
               SWAP_WARN_PCT SWAP_CRIT_PCT \
               CPU_WARN_PCT CPU_CRIT_PCT \
               WARN_THROTTLE_MIN CRIT_THROTTLE_MIN; do
        _sp_require_int "$var" || ok=false
    done
    for var in LOAD_WARN_MULT LOAD_CRIT_MULT; do
        _sp_require_num "$var" || ok=false
    done

    [[ "$ok" == "true" ]]
}
