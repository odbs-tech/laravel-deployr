#!/bin/bash
# Step 6: PHP installation (Ubuntu PPA / Debian sury.org)

step_php() {
    print_header "Step 6 — Installing PHP $PHP_VERSION"

    if [ "${OS_ID:-}" = "ubuntu" ]; then
        LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
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

    apt-get update -qq

    local php_packages=(
        "php${PHP_VERSION}-common"
        "php${PHP_VERSION}-fpm"
        "php${PHP_VERSION}-xml"
        "php${PHP_VERSION}-bcmath"
        "php${PHP_VERSION}-mbstring"
        "php${PHP_VERSION}-zip"
        "php${PHP_VERSION}-curl"
        "php${PHP_VERSION}-gd"
        "php${PHP_VERSION}-intl"
        "php${PHP_VERSION}-imagick"
        "php${PHP_VERSION}-redis"
    )

    if [ "$DB_TYPE" = "mysql" ]; then
        php_packages+=("php${PHP_VERSION}-mysql")
    else
        php_packages+=("php${PHP_VERSION}-pgsql")
    fi

    apt-get install -y "${php_packages[@]}"

    systemctl enable "php${PHP_VERSION}-fpm"
    systemctl start "php${PHP_VERSION}-fpm"

    print_success "PHP $PHP_VERSION installed."
    complete_step 6
}
