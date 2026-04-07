#!/bin/bash
# Step 12: Supervisor queue workers | Step 13: Laravel scheduler cron

step_supervisor() {
    print_header "Step 12 — Configuring Supervisor Queue Workers"

    apt-get install -y supervisor

    # Use redis queue if Redis was installed, otherwise fall back to database
    local queue_driver="database"
    [ "$SETUP_REDIS" = "true" ] && queue_driver="redis"

    cat > "/etc/supervisor/conf.d/laravel-worker.conf" <<SUPEOF
[program:laravel-worker]
process_name=%(program_name)s_%(process_num)02d
command=php ${BASE_PATH}/current/artisan queue:work ${queue_driver} --sleep=3 --tries=3 --max-time=3600
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
user=www-data
numprocs=${WORKER_COUNT}
redirect_stderr=true
stdout_logfile=/var/log/laravel-worker.log
stopwaitsecs=3600
SUPEOF

    systemctl enable supervisor
    systemctl start supervisor
    supervisorctl reread
    supervisorctl update
    supervisorctl start "laravel-worker:*" 2>/dev/null || true

    print_success "Supervisor configured with $WORKER_COUNT $queue_driver worker(s)."
    complete_step 12
}

step_scheduler() {
    print_header "Step 13 — Adding Laravel Scheduler Cron"

    local cron_cmd="* * * * * cd ${BASE_PATH}/current && php artisan schedule:run >> /dev/null 2>&1"

    if ! crontab -u www-data -l 2>/dev/null | grep -q "schedule:run"; then
        (crontab -u www-data -l 2>/dev/null; echo "$cron_cmd") | crontab -u www-data -
        print_success "Laravel scheduler cron added for www-data."
    else
        print_warning "Scheduler cron already exists — skipping."
    fi

    complete_step 13
}
