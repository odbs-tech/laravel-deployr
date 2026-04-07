#!/bin/bash
# deploy.sh — Provision server (once) then deploy with releases structure

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
    # shellcheck source=../steps/11_nodejs.sh
    source "${root}/lib/steps/11_nodejs.sh"
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
    # Load server-level config (PHP version, Redis, provisioning state)
    if [ -f "$SERVER_CONF" ]; then
        # shellcheck source=/dev/null
        source "$SERVER_CONF"
    fi

    # If APP_SLUG not set yet, ask for app name first so we can set the slug
    if [ -z "$APP_SLUG" ]; then
        _ask_app_name_only
    fi

    resolve_config_file

    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
        CURRENT_STEP="${COMPLETED_STEP:-0}"

        if [ "${CURRENT_STEP}" -gt 0 ] && [ "${NON_INTERACTIVE:-false}" != "true" ]; then
            echo ""
            print_warning "Previous state for '${APP_SLUG}' — completed up to step $CURRENT_STEP: ${STEP_NAMES[$CURRENT_STEP]:-unknown}"
            echo ""
            echo -e "  ${YELLOW}1)${NC} Resume from step $((CURRENT_STEP + 1))"
            echo -e "  ${YELLOW}2)${NC} Start fresh (re-ask all questions)"
            echo ""
            ask "Choose" "1" RESUME_CHOICE

            if [ "$RESUME_CHOICE" != "1" ]; then
                CURRENT_STEP=0
                rm -f "$CONFIG_FILE"
                _ask_configuration
            else
                print_success "Resuming '${APP_SLUG}' from step $((CURRENT_STEP + 1))"
                _show_loaded_config
            fi
        elif [ "${CURRENT_STEP}" -eq 0 ]; then
            _ask_configuration
        fi
    else
        _ask_configuration
    fi
}

_ask_app_name_only() {
    if [ "${NON_INTERACTIVE:-false}" = "true" ]; then
        if [ -z "${APP_NAME:-}" ]; then
            print_error "APP_NAME must be set in non-interactive mode."
            exit 1
        fi
        APP_SLUG="$(slugify "$APP_NAME")"
        export APP_SLUG
        return
    fi

    ask "Application name" "Laravel" APP_NAME
    APP_SLUG="$(slugify "$APP_NAME")"
    export APP_SLUG
    print_info "App slug: ${APP_SLUG}"
}

_ask_configuration() {
    print_header "Configuration — ${APP_SLUG}"

    # APP_NAME may already be set if _ask_app_name_only ran
    if [ -z "${APP_NAME:-}" ]; then
        ask "Application name" "Laravel" APP_NAME
        APP_SLUG="$(slugify "$APP_NAME")"
        export APP_SLUG
        resolve_config_file
    fi

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
    # PHP version is per-app — each app can use a different version
    ask "PHP version" "8.4" PHP_VERSION
    ask "Project base directory" "/var/www/${DOMAIN}" BASE_PATH

    ask "Git SSH repo URL (e.g. git@github.com:user/repo.git)" "" GIT_REPO
    while [ -z "$GIT_REPO" ]; do print_error "Cannot be empty."; ask "Git SSH repo URL" "" GIT_REPO; done
    ask "Git branch" "main" GIT_BRANCH

    ask "Supervisor worker count" "8" WORKER_COUNT

    # Server-level options (asked only if server not yet provisioned)
    if [ "${SERVER_PROVISIONED:-false}" != "true" ]; then
        ask_yes_no "Install Redis?" "y" SETUP_REDIS
        REDIS_HOST="127.0.0.1"
        REDIS_PORT="6379"

        ask_yes_no "Install Node.js?" "n" SETUP_NODEJS
        if [ "$SETUP_NODEJS" = "true" ]; then
            ask "Node.js version" "20" NODE_VERSION
        fi
    fi

    ask_yes_no "Run npm build after deploy?" "n" RUN_NPM_BUILD
    if [ "$RUN_NPM_BUILD" = "true" ]; then
        ask "npm build command" "npm run build" NPM_BUILD_CMD
    else
        NPM_BUILD_CMD=""
    fi

    _print_config_summary
    ask_yes_no "Proceed with installation?" "y" PROCEED
    [ "$PROCEED" = "false" ] && { echo "Installation cancelled."; exit 0; }

    save_app_config
    save_server_config
    print_success "Configuration saved."
}

_print_config_summary() {
    print_header "Configuration Summary — ${APP_SLUG}"
    echo -e "  App Name:    ${GREEN}$APP_NAME${NC}"
    echo -e "  Domain:      ${GREEN}$DOMAIN${NC}"
    echo -e "  SSL:         ${GREEN}$SETUP_SSL${NC}"
    echo -e "  Database:    ${GREEN}$DB_TYPE ($DB_NAME)${NC}"
    echo -e "  PHP:         ${GREEN}$PHP_VERSION${NC}"
    echo -e "  Base Dir:    ${GREEN}$BASE_PATH${NC}"
    echo -e "  Git:         ${GREEN}$GIT_REPO ($GIT_BRANCH)${NC}"
    echo -e "  Workers:     ${GREEN}$WORKER_COUNT${NC}"
    echo -e "  Redis:       ${GREEN}${SETUP_REDIS:-false}${NC}"
    echo -e "  Node.js:     ${GREEN}${SETUP_NODEJS:-false}${NC}"
    [ -n "${NPM_BUILD_CMD:-}" ] && echo -e "  npm build:   ${GREEN}$NPM_BUILD_CMD${NC}"
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
    # ── Global infrastructure (runs once per server) ───────────────────────
    if [ "${SERVER_PROVISIONED:-false}" != "true" ]; then
        should_run 1  && step_system_update
        should_run 2  && step_essential_packages
        should_run 3  && step_nginx
        should_run 4  && step_firewall
        should_run 5  && step_ssh_key
        should_run 6  && step_php        # also calls register_php_version
        should_run 7  && step_composer
        should_run 8  && step_database
        should_run 9  && step_redis
        should_run 10 && step_nodejs

        SERVER_PROVISIONED=true
        save_server_config
        print_success "Server infrastructure provisioned."
    else
        print_info "Server already provisioned — skipping infrastructure setup."
    fi

    # ── PHP (per-version — runs whenever a new version is requested) ───────
    _ensure_php_version
}

# Install the app's requested PHP version if not already on this server.
# This is called for every deploy so that adding a second app with a
# different PHP version "just works" without touching the other app.
_ensure_php_version() {
    local ver="${PHP_VERSION:-8.4}"

    if php_version_is_installed "$ver"; then
        print_info "PHP $ver already installed — skipping."
        return
    fi

    print_header "Installing PHP $ver"
    _install_php_for_version "$ver"

    # Mark this version as installed on the server
    register_php_version "$ver"
    print_success "PHP $ver registered in server config."
}

# ─── Release Deploy ───────────────────────────────────────────────────────────

_run_release_deploy() {
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local release_dir="${BASE_PATH}/releases/${timestamp}"
    local shared_dir="${BASE_PATH}/shared"
    local current_link="${BASE_PATH}/current"

    print_header "Deploying ${APP_SLUG} — Release: $timestamp"

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

    # Node.js / npm build (optional)
    if [ -n "${NPM_BUILD_CMD:-}" ]; then
        print_info "Running npm ci..."
        npm ci --prefix "$release_dir"
        print_info "Running: $NPM_BUILD_CMD"
        cd "$release_dir"
        eval "$NPM_BUILD_CMD"
        cd - >/dev/null
    fi

    # Laravel build steps
    print_info "Building Laravel caches..."
    cd "$release_dir"
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
    systemctl is-active --quiet "$fpm_service" \
        && systemctl reload "$fpm_service" 2>/dev/null || true

    # First-time app infrastructure config
    if ! [ -f "/etc/nginx/sites-available/${DOMAIN}" ]; then
        step_nginx_vhost
    fi
    should_run 12 && step_ssl
    should_run 13 && step_supervisor_for_app
    should_run 14 && step_scheduler_for_app

    # Clean up releases older than the latest 3
    _cleanup_old_releases "$BASE_PATH"

    CURRENT_STEP=14
    save_app_config
    rm -f "$CONFIG_FILE"

    print_success "Release $timestamp of '${APP_SLUG}' deployed successfully."
}

# Per-app Supervisor config (named after APP_SLUG so multiple apps don't collide)
step_supervisor_for_app() {
    print_header "Configuring Supervisor — ${APP_SLUG}"

    apt-get install -y supervisor

    local queue_driver="database"
    [ "${SETUP_REDIS:-false}" = "true" ] && queue_driver="redis"

    cat > "/etc/supervisor/conf.d/laravel-${APP_SLUG}-worker.conf" <<SUPEOF
[program:laravel-${APP_SLUG}-worker]
process_name=%(program_name)s_%(process_num)02d
command=php ${BASE_PATH}/current/artisan queue:work ${queue_driver} --sleep=3 --tries=3 --max-time=3600
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
user=www-data
numprocs=${WORKER_COUNT}
redirect_stderr=true
stdout_logfile=/var/log/laravel-${APP_SLUG}-worker.log
stopwaitsecs=3600
SUPEOF

    systemctl enable supervisor
    systemctl start supervisor
    supervisorctl reread
    supervisorctl update
    supervisorctl start "laravel-${APP_SLUG}-worker:*" 2>/dev/null || true

    print_success "Supervisor configured: ${WORKER_COUNT} worker(s) for '${APP_SLUG}'."
    complete_step 13
}

# Per-app scheduler cron entry
step_scheduler_for_app() {
    print_header "Scheduler Cron — ${APP_SLUG}"

    local cron_cmd="* * * * * cd ${BASE_PATH}/current && php artisan schedule:run >> /dev/null 2>&1"

    if crontab -u www-data -l 2>/dev/null | grep -qF "${BASE_PATH}/current"; then
        print_warning "Scheduler cron for '${APP_SLUG}' already exists — skipping."
    else
        (crontab -u www-data -l 2>/dev/null; echo "$cron_cmd") | crontab -u www-data -
        print_success "Scheduler cron added for '${APP_SLUG}'."
    fi

    complete_step 14
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
    if [ "${SETUP_REDIS:-false}" = "true" ]; then
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

REDIS_HOST=${REDIS_HOST:-127.0.0.1}
REDIS_PASSWORD=null
REDIS_PORT=${REDIS_PORT:-6379}

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
    print_header "Deployment Complete — ${APP_SLUG}!"

    echo -e "  ${BOLD}URL:${NC}         https://${DOMAIN}"
    echo -e "  ${BOLD}Base Dir:${NC}    ${BASE_PATH}"
    echo -e "  ${BOLD}Shared .env:${NC} ${BASE_PATH}/shared/.env"
    echo -e "  ${BOLD}Database:${NC}    ${DB_TYPE} (${DB_NAME})"
    echo -e "  ${BOLD}PHP:${NC}         ${PHP_VERSION}"
    echo -e "  ${BOLD}SSL:${NC}         ${SETUP_SSL}"
    echo -e "  ${BOLD}Redis:${NC}       ${SETUP_REDIS:-false}"
    echo -e "  ${BOLD}Node.js:${NC}     ${SETUP_NODEJS:-false}"
    echo -e "  ${BOLD}Workers:${NC}     ${WORKER_COUNT}"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo -e "  1. Edit ${BASE_PATH}/shared/.env  (fill in Mail, AWS credentials)"
    echo -e "  2. Logs: tail -f ${BASE_PATH}/shared/storage/logs/laravel.log"
    echo -e "  3. Workers: supervisorctl status"
    echo -e "  4. Rollback: sudo deployr rollback --app ${APP_SLUG}"
    echo -e "  5. Status:   sudo deployr status --app ${APP_SLUG}"
    echo ""
}
