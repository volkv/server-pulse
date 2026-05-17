#!/usr/bin/env bash
# server-pulse check: Docker containers from an allowlist must be running.

sp_check_docker() {
    [[ "$CHECK_DOCKER" == "true" ]] || return 0
    if ! command -v docker >/dev/null 2>&1; then
        sp_log_warn "CHECK_DOCKER=true but 'docker' is not on PATH; skipping"
        return 0
    fi

    local container state status value message
    for container in $DOCKER_CONTAINERS; do
        state="$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null || echo "missing")"

        case "$state" in
            running) status="OK";   value="$state" ;;
            missing) status="CRIT"; value="container not found" ;;
            *)       status="CRIT"; value="$state" ;;
        esac

        message="Docker container \"${container}\": ${value}"
        sp_state_dispatch "docker:${container}" "$status" "$value" "$message"
    done
}
