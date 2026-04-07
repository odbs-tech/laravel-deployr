#!/bin/bash
# rollback.sh — Roll back to the previous release

rollback_command() {
    check_root

    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "No deployment config found at $CONFIG_FILE. Run 'deployr deploy' first."
        exit 1
    fi

    # shellcheck source=/dev/null
    source "$CONFIG_FILE"

    local releases_dir="${BASE_PATH}/releases"
    local current_link="${BASE_PATH}/current"

    if [ ! -d "$releases_dir" ]; then
        print_error "Releases directory not found: $releases_dir"
        exit 1
    fi

    # Collect sorted release paths
    local releases=()
    while IFS= read -r rel; do
        releases+=("$rel")
    done < <(find "$releases_dir" -mindepth 1 -maxdepth 1 -type d | sort)

    local count="${#releases[@]}"

    if [ "$count" -lt 2 ]; then
        print_error "Only $count release(s) available. At least 2 are needed for rollback."
        exit 1
    fi

    local current_release
    current_release=$(readlink -f "$current_link" 2>/dev/null)
    local current_ts
    current_ts=$(basename "$current_release")

    # Find the release just before current
    local previous_release=""
    local i
    for (( i = count - 1; i >= 0; i-- )); do
        if [ "${releases[$i]}" != "$current_release" ]; then
            previous_release="${releases[$i]}"
            break
        fi
    done

    if [ -z "$previous_release" ]; then
        print_error "Could not find a previous release to roll back to."
        exit 1
    fi

    local previous_ts
    previous_ts=$(basename "$previous_release")

    print_header "Rollback"
    echo -e "  ${RED}Current (rolling back from):${NC}  $current_ts"
    echo -e "  ${GREEN}Previous (rolling back to):${NC}   $previous_ts"
    echo ""

    if [ "${NON_INTERACTIVE:-false}" != "true" ]; then
        ask_yes_no "Roll back to $previous_ts?" "y" CONFIRM_ROLLBACK
        [ "$CONFIRM_ROLLBACK" = "false" ] && { echo "Rollback cancelled."; exit 0; }
    fi

    # Atomic symlink switch
    ln -sfn "$previous_release" "$current_link"
    print_success "Switched current → $previous_ts"

    # Reload Nginx
    if nginx -t 2>/dev/null; then
        systemctl reload nginx
        print_success "Nginx reloaded."
    fi

    # Reload PHP-FPM
    local fpm_service="php${PHP_VERSION:-8.4}-fpm"
    if systemctl is-active --quiet "$fpm_service"; then
        systemctl reload "$fpm_service" 2>/dev/null \
            || systemctl restart "$fpm_service"
        print_success "PHP-FPM reloaded."
    fi

    # Restart Supervisor workers pointing at the new current
    if command -v supervisorctl &>/dev/null; then
        supervisorctl restart "laravel-worker:*" 2>/dev/null || true
        print_success "Queue workers restarted."
    fi

    # Optional database migration rollback
    if [ "${NON_INTERACTIVE:-false}" != "true" ]; then
        ask_yes_no "Run 'artisan migrate:rollback' on the previous release?" "n" DO_MIGRATE_ROLLBACK
        if [ "$DO_MIGRATE_ROLLBACK" = "true" ]; then
            cd "$previous_release"
            php artisan migrate:rollback --force
            print_success "Migration rolled back."
        fi
    fi

    # Optionally delete the bad release
    if [ "${NON_INTERACTIVE:-false}" != "true" ]; then
        ask_yes_no "Delete the bad release ($current_ts)?" "y" DELETE_CURRENT
        if [ "$DELETE_CURRENT" = "true" ]; then
            rm -rf "$current_release"
            print_success "Deleted: $current_ts"
        fi
    fi

    print_success "Rollback complete. Running: $previous_ts"
}
