#!/bin/bash
# deploy.sh — Provision server (once) then deploy with releases structure

# Source all dependencies relative to the deployr root
_load_deploy_deps() {
    local root="$DEPLOYR_ROOT"
    # shellcheck source=../validate.sh
    source "${root}/lib/validate.sh"
    # shellcheck source=../steps/01_system.sh
    source "${root}/lib/steps/01_system.sh"
    # shellcheck source=../steps/02_nginx.sh
    source "${root}/lib/steps/02_nginx.sh"
    # shellcheck source=../steps/03_firewall.sh
    source "${root}/lib/steps/03_firewall.sh"
    # shellcheck source=../steps/04_ssh_key.sh
    source "${root}/lib/steps/04_ssh_key.sh"
    # shellcheck source=../steps/05_php.sh
    source "${root}/lib/steps/05_php.sh"
    # shellcheck source=../steps/06_composer.sh
    source "${root}/lib/steps/06_composer.sh"
    # shellcheck source=../steps/07_database.sh
    source "${root}/lib/steps/07_database.sh"
    # shellcheck source=../steps/08_redis.sh
    source "${root}/lib/steps/08_redis.sh"
    # shellcheck source=../steps/09_vhost.sh
    source "${root}/lib/steps/09_vhost.sh"
    # shellcheck source=../steps/10_workers.sh
    source "${root}/lib/steps/10_workers.sh"
}

deploy_command() {
    _load_deploy_deps
    check_root
    detect_os
    check_disk_space 2048

    _load_or_ask_config
    _run_provisioning
    _run_release_deploy
    _print_deploy_summary
}

# ─── Configuration ────────────────────────────────────────────────────────────

_load_or_ask_config() {
    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
        CURRENT_STEP="${COMPLETED_STEP:-0}"

        if [ "${CURRENT_STEP}" -gt 0 ] && [ "${NON_INTERACTIVE:-false}" != "true" ]; then
            echo ""
            print_warning "Previous state found — completed up to step $CURRENT_STEP: ${STEP_NAMES[$CURRENT_STEP]:-unknown}"
            echo ""
            echo -e "  ${YELLOW}1)${NC} Resume from step $((CURRENT_STEP + 1))"
            echo -e "  ${YELLOW}2)${NC} Start fresh (re-ask all questions)"
            echo ""
            ask "Choose" "1" RESUME_CHOICE

            if [ "$RESUME_CHOICE" != "1" ]; then
                CURRENT_STEP=0
                PROVISIONED=false
                rm -f "$CONFIG_FILE"
                _ask_configuration
            else
                print_success "Resuming from step $((CURRENT_STEP + 1))"
                _show_loaded_config
            fi
        elif [ "${CURRENT_STEP}" -eq 0 ]; then
            _ask_configuration
        fi
    else
        _ask_configuration
    fi
}

_ask_configuration() {
    print_header "Configuration"

    ask "Application name" "Laravel" APP_NAME

    ask "Domain name (e.g. api.example.com)" "" DOMAIN
    while [ -z "$DOMAIN" ]; do
        print_error "Domain name cannot be empty."
        ask "Domain name" "" DOMAIN
    done

    ask_yes_no "Setup SSL (Let's Encrypt)?" "y" SETUP_SSL
    if [ "$SETUP_SSL" = "true" ]; then
        ask "Email for SSL certificate" "" SSL_EMAIL
        while [ -z "$SSL_EMAIL" ]; do
            print_error "Email is required for SSL."
            ask "Email for SSL certificate" "" SSL_EMAIL
        done
        check_dns "$DOMAIN"
    fi

    echo ""
    echo -e "${YELLOW}Database:${NC}  1) PostgreSQL  2) MySQL"
    ask "Choose" "1" DB_CHOICE
    case "$DB_CHOICE" in
        2) DB_TYPE="mysql" ;;
        *) DB_TYPE="postgresql" ;;
    esac

    ask "Database name" "" DB_NAME
    while [ -z "$DB_NAME" ]; do print_error "Cannot be empty."; ask "Database name" "" DB_NAME; done

    ask "Database username" "" DB_USER
    while [ -z "$DB_USER" ]; do print_error "Cannot be empty."; ask "Database username" "" DB_USER; done

    ask_password "Database password" DB_PASS
    while [ -z "$DB_PASS" ]; do print_error "Cannot be empty."; ask_password "Database password" DB_PASS; done

    ask_yes_no "Enable remote database access?" "n" DB_REMOTE_ACCESS

    echo ""
    ask "PHP version" "8.4" PHP_VERSION
    ask "Project base directory" "/var/www/${DOMAIN}" BASE_PATH

    ask "Git SSH repo URL (e.g. git@github.com:user/repo.git)" "" GIT_REPO
    while [ -z "$GIT_REPO" ]; do print_error "Cannot be empty."; ask "Git SSH repo URL" "" GIT_REPO; done
    ask "Git branch" "main" GIT_BRANCH

    ask "Supervisor worker count" "8" WORKER_COUNT
    ask_yes_no "Install Redis?" "y" SETUP_REDIS
    REDIS_HOST="127.0.0.1"
    REDIS_PORT="6379"

    _print_config_summary
    ask_yes_no "Proceed with installation?" "y" PROCEED
    [ "$PROCEED" = "false" ] && { echo "Installation cancelled."; exit 0; }

    save_config
    print_success "Configuration saved."
}

_print_config_summary() {
    print_header "Configuration Summary"
    echo -e "  App Name:    ${GREEN}$APP_NAME${NC}"
    echo -e "  Domain:      ${GREEN}$DOMAIN${NC}"
    echo -e "  SSL:         ${GREEN}$SETUP_SSL${NC}"
    echo -e "  Database:    ${GREEN}$DB_TYPE ($DB_NAME)${NC}"
    echo -e "  PHP:         ${GREEN}$PHP_VERSION${NC}"
    echo -e "  Base Dir:    ${GREEN}$BASE_PATH${NC}"
    echo -e "  Git:         ${GREEN}$GIT_REPO ($GIT_BRANCH)${NC}"
    echo -e "  Workers:     ${GREEN}$WORKER_COUNT${NC}"
    echo -e "  Redis:       ${GREEN}$SETUP_REDIS${NC}"
    echo ""
}

_show_loaded_config() {
    echo ""
    echo -e "  App:         ${GREEN}$APP_NAME${NC}"
    echo -e "  Domain:      ${GREEN}$DOMAIN${NC}"
    echo -e "  Database:    ${GREEN}$DB_TYPE ($DB_NAME)${NC}"
    echo -e "  PHP:         ${GREEN}$PHP_VERSION${NC}"
    echo -e "  Git:         ${GREEN}$GIT_REPO ($GIT_BRANCH)${NC}"
    echo ""
}

# ─── Provisioning ─────────────────────────────────────────────────────────────

_run_provisioning() {
    if [ "${PROVISIONED:-false}" = "true" ]; then
        print_info "Server already provisioned — skipping infrastructure setup."
        return
    fi

    should_run 1  && step_system_update
    should_run 2  && step_essential_packages
    should_run 3  && step_nginx
    should_run 4  && step_firewall
    should_run 5  && step_ssh_key
    should_run 6  && step_php
    should_run 7  && step_composer
    should_run 8  && step_database
    should_run 9  && step_redis

    PROVISIONED=true
    save_config
    print_success "Server provisioning complete."
}

# ─── Release Deploy ───────────────────────────────────────────────────────────

_run_release_deploy() {
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local release_dir="${BASE_PATH}/releases/${timestamp}"
    local shared_dir="${BASE_PATH}/shared"
    local current_link="${BASE_PATH}/current"

    print_header "Deploying Release: $timestamp"

    # Prepare shared directory tree (idempotent)
    mkdir -p \
        "${shared_dir}/storage/app/public" \
        "${shared_dir}/storage/framework/sessions" \
        "${shared_dir}/storage/framework/views" \
        "${shared_dir}/storage/framework/cache" \
        "${shared_dir}/storage/logs" \
        "${BASE_PATH}/releases"

    # Clone project into the release directory
    print_info "Cloning $GIT_REPO ($GIT_BRANCH)..."
    git clone -b "$GIT_BRANCH" "$GIT_REPO" "$release_dir"

    # Create shared .env on first deploy
    if [ ! -f "${shared_dir}/.env" ]; then
        _create_env "${shared_dir}/.env"
    fi

    # Symlink shared resources into the release
    rm -rf "${release_dir}/storage"
    ln -sfn "${shared_dir}/storage" "${release_dir}/storage"
    ln -sfn "${shared_dir}/.env"    "${release_dir}/.env"

    # Install PHP dependencies
    print_info "Running composer install..."
    cd "$release_dir"
    composer install --no-dev --optimize-autoloader --no-interaction

    # Laravel build steps
    print_info "Building Laravel caches..."
    php artisan config:cache
    php artisan route:cache
    php artisan view:cache

    print_info "Running migrations..."
    php artisan migrate --force

    # Set permissions
    chown -R www-data:www-data "$release_dir"
    chown -R www-data:www-data "$shared_dir"
    chmod -R 775 "${shared_dir}/storage"

    # Atomic symlink switch → zero-downtime
    ln -sfn "$release_dir" "$current_link"
    print_success "Switched current → $timestamp"

    # Reload services
    if nginx -t 2>/dev/null; then
        systemctl reload nginx
    fi
    local fpm_service="php${PHP_VERSION}-fpm"
    systemctl is-active --quiet "$fpm_service" && systemctl reload "$fpm_service" 2>/dev/null || true

    # First-time infrastructure config
    if ! [ -f "/etc/nginx/sites-available/${DOMAIN}" ]; then
        step_nginx_vhost
    fi
    should_run 11 && step_ssl
    should_run 12 && step_supervisor
    should_run 13 && step_scheduler

    # Clean up releases older than the latest 3
    _cleanup_old_releases "$BASE_PATH"

    CURRENT_STEP=13
    PROVISIONED=true
    save_config
    rm -f "$CONFIG_FILE"

    print_success "Release $timestamp deployed successfully."
}

_create_env() {
    local env_file="$1"
    local db_connection db_port
    local cache_driver queue_connection session_driver

    if [ "$DB_TYPE" = "mysql" ]; then
        db_connection="mysql"
        db_port="3306"
    else
        db_connection="pgsql"
        db_port="5432"
    fi

    # Only use redis drivers when Redis is actually installed
    if [ "$SETUP_REDIS" = "true" ]; then
        cache_driver="redis"
        queue_connection="redis"
        session_driver="redis"
    else
        cache_driver="file"
        queue_connection="database"
        session_driver="file"
    fi

    local app_key_value
    app_key_value="base64:$(openssl rand -base64 32)"

    cat > "$env_file" <<ENVEOF
APP_NAME="${APP_NAME}"
APP_ENV=production
APP_KEY=${app_key_value}
APP_DEBUG=false
APP_URL=https://${DOMAIN}

LOG_CHANNEL=stack
LOG_LEVEL=error

DB_CONNECTION=${db_connection}
DB_HOST=127.0.0.1
DB_PORT=${db_port}
DB_DATABASE=${DB_NAME}
DB_USERNAME=${DB_USER}
DB_PASSWORD=${DB_PASS}

BROADCAST_DRIVER=log
CACHE_DRIVER=${cache_driver}
FILESYSTEM_DISK=local
QUEUE_CONNECTION=${queue_connection}
SESSION_DRIVER=${session_driver}
SESSION_LIFETIME=120

REDIS_HOST=${REDIS_HOST}
REDIS_PASSWORD=null
REDIS_PORT=${REDIS_PORT}

MAIL_MAILER=smtp
MAIL_HOST=
MAIL_PORT=587
MAIL_USERNAME=
MAIL_PASSWORD=
MAIL_ENCRYPTION=tls
MAIL_FROM_ADDRESS=noreply@${DOMAIN}
MAIL_FROM_NAME="\${APP_NAME}"

AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
AWS_DEFAULT_REGION=
AWS_BUCKET=
ENVEOF

    chmod 640 "$env_file"
    print_success ".env created at $env_file"
}

_cleanup_old_releases() {
    local base_path="$1"
    local keep=3
    local releases_dir="${base_path}/releases"
    local count
    count=$(find "${releases_dir}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)

    if [ "$count" -gt "$keep" ]; then
        local to_delete=$(( count - keep ))
        find "${releases_dir}" -mindepth 1 -maxdepth 1 -type d | sort | head -n "$to_delete" \
        | while IFS= read -r old_release; do
            rm -rf "$old_release"
            print_info "Removed old release: $(basename "$old_release")"
        done
    fi
}

# ─── Summary ──────────────────────────────────────────────────────────────────

_print_deploy_summary() {
    print_header "Deployment Complete!"

    echo -e "  ${BOLD}URL:${NC}         https://${DOMAIN}"
    echo -e "  ${BOLD}Base Dir:${NC}    ${BASE_PATH}"
    echo -e "  ${BOLD}Shared .env:${NC} ${BASE_PATH}/shared/.env"
    echo -e "  ${BOLD}Database:${NC}    ${DB_TYPE} (${DB_NAME})"
    echo -e "  ${BOLD}PHP:${NC}         ${PHP_VERSION}"
    echo -e "  ${BOLD}SSL:${NC}         ${SETUP_SSL}"
    echo -e "  ${BOLD}Redis:${NC}       ${SETUP_REDIS}"
    echo -e "  ${BOLD}Workers:${NC}     ${WORKER_COUNT}"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo -e "  1. Edit ${BASE_PATH}/shared/.env  (fill in Mail, AWS credentials)"
    echo -e "  2. Logs: tail -f ${BASE_PATH}/shared/storage/logs/laravel.log"
    echo -e "  3. Workers: supervisorctl status"
    echo -e "  4. Rollback: sudo deployr rollback"
    echo ""
}
