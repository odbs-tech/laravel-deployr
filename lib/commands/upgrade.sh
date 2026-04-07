#!/bin/bash
# upgrade.sh — Upgrade server stack (packages, Composer, PHP-FPM, Nginx)

upgrade_command() {
    check_root

    print_header "Upgrading Stack"

    print_info "Updating package lists..."
    apt-get update -qq

    print_info "Upgrading system packages..."
    apt-get upgrade -y

    if command -v composer &>/dev/null; then
        print_info "Upgrading Composer..."
        composer self-update
        print_success "Composer: $(composer --version)"
    fi

    if [ -f "$SERVER_CONF" ]; then
        # shellcheck source=/dev/null
        source "$SERVER_CONF"

        # Restart FPM for every installed PHP version
        local installed="${INSTALLED_PHP_VERSIONS:-}"
        if [ -n "$installed" ]; then
            for ver in $installed; do
                local fpm_service="php${ver}-fpm"
                if systemctl is-active --quiet "$fpm_service"; then
                    systemctl restart "$fpm_service"
                    print_success "PHP-FPM ($ver) restarted."
                fi
            done
        fi
    fi

    if systemctl is-active --quiet nginx; then
        nginx -t && systemctl reload nginx
        print_success "Nginx reloaded."
    fi

    if systemctl is-active --quiet redis-server; then
        systemctl restart redis-server
        print_success "Redis restarted."
    fi

    if systemctl is-active --quiet supervisor; then
        supervisorctl reread 2>/dev/null || true
        supervisorctl update 2>/dev/null || true
        print_success "Supervisor updated."
    fi

    print_success "Stack upgrade complete."
}
