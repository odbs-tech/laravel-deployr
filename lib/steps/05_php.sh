#!/bin/bash
# Step 6: PHP installation (Ubuntu PPA / Debian sury.org)
# PHP_VERSION is per-app and must be set before calling these functions.

step_php() {
    print_header "Step 6 — Installing PHP $PHP_VERSION"
    _install_php_for_version "$PHP_VERSION"
    register_php_version "$PHP_VERSION"
    complete_step 6
}

# Install (or ensure installed) a specific PHP version.
# Safe to call multiple times for different versions on the same server.
_install_php_for_version() {
    local ver="$1"

    _ensure_php_repo

    apt-get update -qq

    local php_packages=(
        "php${ver}-common"
        "php${ver}-fpm"
        "php${ver}-xml"
        "php${ver}-bcmath"
        "php${ver}-mbstring"
        "php${ver}-zip"
        "php${ver}-curl"
        "php${ver}-gd"
        "php${ver}-intl"
        "php${ver}-imagick"
        "php${ver}-redis"
    )

    if [ "${DB_TYPE:-postgresql}" = "mysql" ]; then
        php_packages+=("php${ver}-mysql")
    else
        php_packages+=("php${ver}-pgsql")
    fi

    apt-get install -y "${php_packages[@]}"

    systemctl enable "php${ver}-fpm"
    systemctl start  "php${ver}-fpm"

    _configure_opcache "$ver"

    print_success "PHP $ver installed and running."
}

# Add the PHP PPA/repository (idempotent — safe to call multiple times)
_ensure_php_repo() {
    if [ "${OS_ID:-}" = "ubuntu" ]; then
        if ! grep -rq "ondrej/php" /etc/apt/sources.list.d/ 2>/dev/null; then
            LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
        fi
    elif [ "${OS_ID:-}" = "debian" ]; then
        if ! grep -rq "sury.org/php" /etc/apt/sources.list.d/ 2>/dev/null; then
            print_info "Adding sury.org PHP repository for Debian..."
            curl -sSLo /tmp/php-sury.gpg https://packages.sury.org/php/apt.gpg
            gpg --dearmor < /tmp/php-sury.gpg > /usr/share/keyrings/php-sury.gpg
            echo "deb [signed-by=/usr/share/keyrings/php-sury.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" \
                > /etc/apt/sources.list.d/php-sury.list
            rm -f /tmp/php-sury.gpg
        fi
    else
        print_warning "Unknown OS for PHP PPA. Attempting default repositories."
    fi
}

_configure_opcache() {
    local ver="$1"
    local ini_dir="/etc/php/${ver}/fpm/conf.d"
    local ini_file="${ini_dir}/99-laravel-opcache.ini"

    mkdir -p "$ini_dir"

    cat > "$ini_file" <<INIEOF
; Laravel Deployr — Production Opcache settings
[opcache]
opcache.enable=1
opcache.memory_consumption=256
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=20000
opcache.revalidate_freq=0
; Timestamp validation disabled in production for maximum performance.
; PHP-FPM is reloaded on each deploy so stale caches are never an issue.
opcache.validate_timestamps=0
opcache.save_comments=1
opcache.fast_shutdown=1
INIEOF

    systemctl restart "php${ver}-fpm"
    print_success "Opcache configured: $ini_file"
}

# Public alias kept for any external callers
step_opcache() { _configure_opcache "${PHP_VERSION}"; }
