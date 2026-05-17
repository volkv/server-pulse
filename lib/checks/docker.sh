#!/usr/bin/env bash
# server-pulse check: Docker containers from an allowlist must be running.
#
# If `docker` is unavailable while CHECK_DOCKER=true, that is itself a
# CRITICAL self-check failure — silently skipping would hide problems.

sp_check_docker() {
    [[ "$CHECK_DOCKER" == "true" ]] || return 0

    if ! command -v docker >/dev/null 2>&1; then
        sp_state_dispatch "docker:_runtime" "CRIT" "docker missing" \
            "CHECK_DOCKER=true but 'docker' is not on PATH — containers cannot be verified"
        return 0
    fi
    # Recovery path: clear stale runtime alert once docker is back.
    sp_state_dispatch "docker:_runtime" "OK" "docker present" "Docker runtime available"

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
