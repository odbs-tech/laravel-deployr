#!/bin/bash
# status.sh — Service health, release list, and deployment overview

status_command() {
    # Load server-level config (INSTALLED_PHP_VERSIONS, SETUP_REDIS, etc.)
    [ -f "$SERVER_CONF" ] && source "$SERVER_CONF"

    if [ -n "${APP_SLUG:-}" ]; then
        # ── Single-app detail ────────────────────────────────────────────────
        resolve_config_file
        if [ ! -f "$CONFIG_FILE" ]; then
            print_error "No config found for app '${APP_SLUG}'."
            exit 1
        fi
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"

        print_header "Status — ${APP_SLUG}"
        _show_services
        _show_releases "$BASE_PATH"
        _show_workers "$APP_SLUG"
        _show_deployment_info
    else
        # ── All-apps overview ────────────────────────────────────────────────
        print_header "Laravel Deployr — All Apps"
        _show_services

        local slugs=()
        mapfile -t slugs < <(list_app_slugs)

        if [ "${#slugs[@]}" -eq 0 ]; then
            print_warning "No apps deployed yet. Run: sudo deployr deploy --app <name>"
        else
            printf "  %-20s  %-35s  %-7s  %s\n" \
                "${BOLD}APP${NC}" "DOMAIN" "PHP" "CURRENT RELEASE"
            printf "  %-20s  %-35s  %-7s  %s\n" \
                "----" "------" "---" "---------------"

            for slug in "${slugs[@]}"; do
                local app_conf="${DEPLOYR_CONF_DIR}/${slug}.conf"
                # shellcheck source=/dev/null
                source "$app_conf"

                local current_ts="(none)"
                if [ -n "${BASE_PATH:-}" ] && [ -L "${BASE_PATH}/current" ]; then
                    current_ts=$(basename "$(readlink -f "${BASE_PATH}/current")" 2>/dev/null || echo "?")
                fi

                printf "  %-20s  %-35s  %-7s  %s\n" \
                    "${GREEN}${slug}${NC}" \
                    "${DOMAIN:-n/a}" \
                    "${PHP_VERSION:-?}" \
                    "$current_ts"
            done
            echo ""
        fi

        _show_disk
    fi
}

# ─── Section helpers ──────────────────────────────────────────────────────────

_show_services() {
    echo -e "${BOLD}Services:${NC}"
    _check_service "nginx"

    # Show FPM status for every installed PHP version
    local installed_versions="${INSTALLED_PHP_VERSIONS:-}"
    if [ -z "$installed_versions" ] && [ -f "$SERVER_CONF" ]; then
        installed_versions=$(grep "^INSTALLED_PHP_VERSIONS=" "$SERVER_CONF" \
            | cut -d= -f2- | tr -d '"')
    fi
    if [ -n "$installed_versions" ]; then
        for ver in $installed_versions; do
            _check_service "php${ver}-fpm"
        done
    else
        # Fallback: show the current app's FPM if known
        [ -n "${PHP_VERSION:-}" ] && _check_service "php${PHP_VERSION}-fpm"
    fi

    _check_service "redis-server"
    _check_service "supervisor"
    echo ""
}

_show_releases() {
    local base_path="$1"
    if [ -z "$base_path" ] || [ ! -d "${base_path}/releases" ]; then
        return
    fi

    local current_release
    current_release=$(readlink -f "${base_path}/current" 2>/dev/null || echo "")

    echo -e "${BOLD}Releases:${NC}"
    local idx=0
    while IFS= read -r rel; do
        local ts
        ts=$(basename "$rel")
        local marker=""
        [ "$rel" = "$current_release" ] && marker=" ${GREEN}← current${NC}"
        idx=$(( idx + 1 ))
        echo -e "  $(printf '%2d' "$idx"). $ts$marker"
    done < <(find "${base_path}/releases" -mindepth 1 -maxdepth 1 -type d | sort -r)
    echo ""
}

_show_workers() {
    local slug="$1"
    if command -v supervisorctl &>/dev/null; then
        echo -e "${BOLD}Queue Workers (${slug}):${NC}"
        supervisorctl status "laravel-${slug}-worker:*" 2>/dev/null \
            | awk '{printf "  %s\n", $0}' \
            || echo "  (none or supervisorctl unavailable)"
        echo ""
    fi
}

_show_deployment_info() {
    echo -e "${BOLD}Deployment:${NC}"
    [ -n "${DOMAIN:-}" ]      && echo -e "  URL:      https://${DOMAIN}"
    [ -n "${BASE_PATH:-}" ]   && echo -e "  Base:     ${BASE_PATH}"
    [ -n "${DB_TYPE:-}" ]     && echo -e "  Database: ${DB_TYPE} (${DB_NAME:-n/a})"
    [ -n "${PHP_VERSION:-}" ] && echo -e "  PHP:      ${PHP_VERSION} (php${PHP_VERSION}-fpm)"
    # Show all installed versions from server config
    if [ -f "$SERVER_CONF" ]; then
        local installed
        installed=$(grep "^INSTALLED_PHP_VERSIONS=" "$SERVER_CONF" | cut -d= -f2- | tr -d '"')
        [ -n "$installed" ] && echo -e "  PHP (server): $installed"
    fi
    echo ""
    _show_disk
}

_show_disk() {
    echo -e "${BOLD}Disk Usage:${NC}"
    df -h / | awk 'NR==2 {printf "  Used: %s / %s (%s)\n", $3, $2, $5}'
    echo ""
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
