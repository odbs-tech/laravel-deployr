#!/bin/bash
# status.sh — Show services, releases, and deployment info

status_command() {
    print_header "Laravel Deployr — Status"

    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
    fi

    local php_ver="${PHP_VERSION:-8.4}"

    # ── Services ────────────────────────────────────────────────
    echo -e "${BOLD}Services:${NC}"
    _check_service "nginx"
    _check_service "php${php_ver}-fpm"
    _check_service "redis-server"
    _check_service "supervisor"
    echo ""

    # ── Queue Workers ────────────────────────────────────────────
    if command -v supervisorctl &>/dev/null; then
        echo -e "${BOLD}Queue Workers:${NC}"
        supervisorctl status 2>/dev/null \
            | awk '{printf "  %s\n", $0}' \
            || echo "  supervisorctl unavailable"
        echo ""
    fi

    # ── Releases ─────────────────────────────────────────────────
    if [ -n "${BASE_PATH:-}" ] && [ -d "${BASE_PATH}/releases" ]; then
        local current_release
        current_release=$(readlink -f "${BASE_PATH}/current" 2>/dev/null)

        echo -e "${BOLD}Releases:${NC}"
        local idx=0
        while IFS= read -r rel; do
            local ts
            ts=$(basename "$rel")
            local marker=""
            [ "$rel" = "$current_release" ] && marker=" ${GREEN}← current${NC}"
            idx=$(( idx + 1 ))
            echo -e "  $(printf '%2d' "$idx"). $ts$marker"
        done < <(find "${BASE_PATH}/releases" -mindepth 1 -maxdepth 1 -type d | sort -r)
        echo ""
    fi

    # ── Disk Usage ───────────────────────────────────────────────
    echo -e "${BOLD}Disk Usage:${NC}"
    df -h / | awk 'NR==2 {printf "  Used: %s / %s (%s)\n", $3, $2, $5}'
    echo ""

    # ── Deployment Info ──────────────────────────────────────────
    if [ -n "${DOMAIN:-}" ]; then
        echo -e "${BOLD}Deployment:${NC}"
        echo -e "  URL:      https://${DOMAIN}"
        [ -n "${BASE_PATH:-}" ] && echo -e "  Base:     ${BASE_PATH}"
        [ -n "${DB_TYPE:-}" ]   && echo -e "  Database: ${DB_TYPE} (${DB_NAME:-n/a})"
        [ -n "${php_ver:-}" ]   && echo -e "  PHP:      ${php_ver}"
        echo ""
    fi
}

_check_service() {
    local svc="$1"
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        echo -e "  ${GREEN}[running]${NC}  $svc"
    elif systemctl list-unit-files --quiet "${svc}.service" 2>/dev/null | grep -q "$svc"; then
        echo -e "  ${RED}[stopped]${NC}  $svc"
    else
        echo -e "  ${YELLOW}[n/a]${NC}      $svc"
    fi
}
