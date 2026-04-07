#!/bin/bash
# Step 10: Nginx virtual host | Step 11: SSL certificate

step_nginx_vhost() {
    print_header "Step 10 — Configuring Nginx Virtual Host"

    # Serve from the current symlink so every release swap is instant
    local web_root="${BASE_PATH}/current/public"

    cat > "/etc/nginx/sites-available/${DOMAIN}" <<NGINXEOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};
    root ${web_root};

    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";

    index index.php index.html;
    charset utf-8;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    error_page 404 /index.php;

    location ~ \.php\$ {
        fastcgi_pass unix:/var/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }

    client_max_body_size 50M;
}
NGINXEOF

    ln -sf "/etc/nginx/sites-available/${DOMAIN}" "/etc/nginx/sites-enabled/${DOMAIN}"
    rm -f /etc/nginx/sites-enabled/default
    nginx -t && systemctl reload nginx

    complete_step 10
}

step_ssl() {
    if [ "$SETUP_SSL" = "true" ]; then
        print_header "Step 11 — Installing SSL Certificate"

        apt-get install -y certbot python3-certbot-nginx
        certbot --nginx \
            -d "$DOMAIN" \
            --non-interactive \
            --agree-tos \
            -m "$SSL_EMAIL" \
            --redirect

        print_success "SSL certificate installed for $DOMAIN."

        if ! crontab -l 2>/dev/null | grep -q "certbot renew"; then
            (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet && systemctl reload nginx") \
                | crontab -
            print_success "SSL auto-renewal cron added."
        fi
    else
        print_info "Step 11 — Skipping SSL (not selected)"
    fi

    complete_step 11
}
