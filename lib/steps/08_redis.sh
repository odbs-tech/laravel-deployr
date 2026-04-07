#!/bin/bash
# Step 9: Redis (optional)

step_redis() {
    if [ "$SETUP_REDIS" = "true" ]; then
        print_header "Step 9 — Installing Redis"

        apt-get install -y redis-server

        if grep -q "^supervised" /etc/redis/redis.conf; then
            sed -i 's/^supervised.*/supervised systemd/' /etc/redis/redis.conf
        else
            echo "supervised systemd" >> /etc/redis/redis.conf
        fi

        systemctl enable redis-server
        systemctl restart redis-server
        print_success "Redis installed and running."
    else
        print_info "Step 9 — Skipping Redis (not selected)"
    fi

    complete_step 9
}
