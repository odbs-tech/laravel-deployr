#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

CONFIG_FILE="/root/.laravel-deployr.conf"
CURRENT_STEP=0

# ============================================================
# Helper Functions
# ============================================================
print_header() {
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}========================================${NC}\n"
}

print_success() { echo -e "${GREEN}[OK] $1${NC}"; }
print_warning() { echo -e "${YELLOW}[!] $1${NC}"; }
print_error() { echo -e "${RED}[ERROR] $1${NC}"; }

ask() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    if [ -n "$default" ]; then
        read -rp "$(echo -e "${YELLOW}$prompt ${NC}[${GREEN}$default${NC}]: ")" input
        eval "$var_name=\"${input:-$default}\""
    else
        read -rp "$(echo -e "${YELLOW}$prompt: ${NC}")" input
        eval "$var_name=\"$input\""
    fi
}

ask_password() {
    local prompt="$1"
    local var_name="$2"
    read -srp "$(echo -e "${YELLOW}$prompt: ${NC}")" input
    echo ""
    eval "$var_name=\"$input\""
}

ask_yes_no() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    if [ "$default" = "y" ]; then
        read -rp "$(echo -e "${YELLOW}$prompt ${NC}[${GREEN}Y/n${NC}]: ")" input
        input="${input:-y}"
    else
        read -rp "$(echo -e "${YELLOW}$prompt ${NC}[${GREEN}y/N${NC}]: ")" input
        input="${input:-n}"
    fi
    case "$input" in
        [yY]) eval "$var_name=true" ;;
        *) eval "$var_name=false" ;;
    esac
}

save_config() {
    cat > "$CONFIG_FILE" <<CFGEOF
COMPLETED_STEP=${CURRENT_STEP}
APP_NAME="${APP_NAME}"
DOMAIN="${DOMAIN}"
SETUP_SSL="${SETUP_SSL}"
SSL_EMAIL="${SSL_EMAIL}"
DB_TYPE="${DB_TYPE}"
DB_NAME="${DB_NAME}"
DB_USER="${DB_USER}"
DB_PASS="${DB_PASS}"
DB_REMOTE_ACCESS="${DB_REMOTE_ACCESS}"
PHP_VERSION="${PHP_VERSION}"
PROJECT_PATH="${PROJECT_PATH}"
GIT_REPO="${GIT_REPO}"
GIT_BRANCH="${GIT_BRANCH}"
WORKER_COUNT="${WORKER_COUNT}"
SETUP_REDIS="${SETUP_REDIS}"
REDIS_HOST="${REDIS_HOST}"
REDIS_PORT="${REDIS_PORT}"
CFGEOF
    chmod 600 "$CONFIG_FILE"
}

complete_step() {
    CURRENT_STEP=$1
    save_config
    print_success "Step $1 completed."
}

should_run() {
    [ "$CURRENT_STEP" -lt "$1" ]
}

STEP_NAMES=(
    ""
    "System Update"
    "Essential Packages"
    "Nginx Install"
    "Firewall"
    "SSH Key"
    "PHP"
    "Composer"
    "Database"
    "Redis"
    "Git Clone"
    ".env File"
    "Composer Install"
    "Laravel Cache & Migrate"
    "File Permissions"
    "Nginx Virtual Host"
    "SSL Certificate"
    "Supervisor"
    "Scheduler Cron"
)

# ============================================================
# Banner & Root Check
# ============================================================
echo -e "${CYAN}"
echo '  _                          _   ____             _                 '
echo ' | |    __ _ _ __ __ ___   _| | |  _ \  ___ _ __ | | ___  _   _ _ __ '
echo ' | |   / _` | `__/ _` \ \ / / | | | | |/ _ \ `_ \| |/ _ \| | | | `__|'
echo ' | |__| (_| | | | (_| |\ V /| | | |_| |  __/ |_) | | (_) | |_| | |   '
echo ' |_____\__,_|_|  \__,_| \_/ |_| |____/ \___| .__/|_|\___/ \__, |_|   '
echo '                                             |_|            |___/      '
echo -e "${NC}"
print_header "Laravel Deployr - Server Setup"

if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root. Use 'sudo bash setup.sh'."
    exit 1
fi

# ============================================================
# OS Detection
# ============================================================
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME="$NAME"
    OS_VERSION="$VERSION_ID"
    OS_ID="$ID"
    print_success "Detected OS: $OS_NAME $OS_VERSION"
else
    print_error "Could not detect OS. /etc/os-release not found."
    exit 1
fi

if [[ "$OS_ID" != "ubuntu" && "$OS_ID" != "debian" ]]; then
    print_warning "This script is optimized for Ubuntu/Debian. Current OS: $OS_NAME"
    ask_yes_no "Continue anyway?" "n" CONTINUE
    if [ "$CONTINUE" = "false" ]; then exit 1; fi
fi

# ============================================================
# Resume or Fresh Start
# ============================================================
RESUME_STEP=0

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    RESUME_STEP=${COMPLETED_STEP:-0}

    if [ "$RESUME_STEP" -gt 0 ]; then
        echo ""
        print_warning "Previous installation found — failed/stopped at step $RESUME_STEP: ${STEP_NAMES[$RESUME_STEP]}"
        echo ""
        echo -e "  ${YELLOW}1)${NC} Resume from step $((RESUME_STEP + 1)): ${GREEN}${STEP_NAMES[$((RESUME_STEP + 1))]}${NC}"
        echo -e "  ${YELLOW}2)${NC} Start fresh (re-ask all questions)"
        echo ""
        ask "Choose" "1" RESUME_CHOICE

        if [ "$RESUME_CHOICE" = "1" ]; then
            CURRENT_STEP=$RESUME_STEP
            print_success "Resuming from step $((CURRENT_STEP + 1)): ${STEP_NAMES[$((CURRENT_STEP + 1))]}"
            echo ""
            echo -e "  App Name:       ${GREEN}$APP_NAME${NC}"
            echo -e "  Domain:         ${GREEN}$DOMAIN${NC}"
            echo -e "  Database:       ${GREEN}$DB_TYPE ($DB_NAME)${NC}"
            echo -e "  PHP:            ${GREEN}$PHP_VERSION${NC}"
            echo -e "  Git:            ${GREEN}$GIT_REPO ($GIT_BRANCH)${NC}"
            echo ""
        else
            CURRENT_STEP=0
            rm -f "$CONFIG_FILE"
        fi
    fi
fi

# ============================================================
# Interactive Questions (skip if resuming)
# ============================================================
if [ "$CURRENT_STEP" -eq 0 ]; then
    print_header "Configuration"

    # App Name
    ask "Application name" "Laravel" APP_NAME

    # Domain
    ask "Domain name (e.g. api.example.com)" "" DOMAIN
    while [ -z "$DOMAIN" ]; do
        print_error "Domain name cannot be empty."
        ask "Domain name (e.g. api.example.com)" "" DOMAIN
    done

    # SSL
    ask_yes_no "Setup SSL (Let's Encrypt)?" "y" SETUP_SSL

    if [ "$SETUP_SSL" = "true" ]; then
        ask "Email for SSL certificate" "" SSL_EMAIL
        while [ -z "$SSL_EMAIL" ]; do
            print_error "Email is required for SSL."
            ask "Email for SSL certificate" "" SSL_EMAIL
        done
    fi

    # Database
    echo ""
    echo -e "${YELLOW}Database selection:${NC}"
    echo "  1) PostgreSQL"
    echo "  2) MySQL"
    ask "Database" "1" DB_CHOICE
    case "$DB_CHOICE" in
        2) DB_TYPE="mysql" ;;
        *) DB_TYPE="postgresql" ;;
    esac
    print_success "Database: $DB_TYPE"

    ask "Database name" "" DB_NAME
    while [ -z "$DB_NAME" ]; do
        print_error "Database name cannot be empty."
        ask "Database name" "" DB_NAME
    done
    ask "Database username" "" DB_USER
    while [ -z "$DB_USER" ]; do
        print_error "Username cannot be empty."
        ask "Database username" "" DB_USER
    done
    ask_password "Database password" DB_PASS
    while [ -z "$DB_PASS" ]; do
        print_error "Password cannot be empty."
        ask_password "Database password" DB_PASS
    done
    ask_yes_no "Enable remote database access?" "n" DB_REMOTE_ACCESS

    # PHP
    echo ""
    ask "PHP version" "8.4" PHP_VERSION

    # Project path
    ask "Project directory" "/var/www/$DOMAIN" PROJECT_PATH

    # Git repo
    ask "Git SSH repo URL (e.g. git@github.com:user/repo.git)" "" GIT_REPO
    while [ -z "$GIT_REPO" ]; do
        print_error "Git repo URL cannot be empty."
        ask "Git SSH repo URL" "" GIT_REPO
    done
    ask "Git branch" "main" GIT_BRANCH

    # Supervisor
    ask "Supervisor worker count" "8" WORKER_COUNT

    # Redis
    ask_yes_no "Install Redis?" "y" SETUP_REDIS
    REDIS_HOST="127.0.0.1"
    REDIS_PORT="6379"

    # ============================================================
    # Summary
    # ============================================================
    print_header "Configuration Summary"
    echo -e "  App Name:       ${GREEN}$APP_NAME${NC}"
    echo -e "  Domain:         ${GREEN}$DOMAIN${NC}"
    echo -e "  SSL:            ${GREEN}$SETUP_SSL${NC}"
    echo -e "  Database:       ${GREEN}$DB_TYPE${NC}"
    echo -e "  DB Name:        ${GREEN}$DB_NAME${NC}"
    echo -e "  DB User:        ${GREEN}$DB_USER${NC}"
    echo -e "  DB Remote:      ${GREEN}$DB_REMOTE_ACCESS${NC}"
    echo -e "  PHP Version:    ${GREEN}$PHP_VERSION${NC}"
    echo -e "  Project Dir:    ${GREEN}$PROJECT_PATH${NC}"
    echo -e "  Git Repo:       ${GREEN}$GIT_REPO${NC}"
    echo -e "  Git Branch:     ${GREEN}$GIT_BRANCH${NC}"
    echo -e "  Workers:        ${GREEN}$WORKER_COUNT${NC}"
    echo -e "  Redis:          ${GREEN}$SETUP_REDIS${NC}"
    echo ""
    ask_yes_no "Proceed with installation?" "y" PROCEED
    if [ "$PROCEED" = "false" ]; then
        echo "Installation cancelled."
        exit 0
    fi

    save_config
    print_success "Config saved to $CONFIG_FILE"
fi

# ============================================================
# Step 1: System Update
# ============================================================
if should_run 1; then
    print_header "Step 1/18 — Updating System"
    apt update && apt upgrade -y
    complete_step 1
fi

# ============================================================
# Step 2: Essential Packages
# ============================================================
if should_run 2; then
    print_header "Step 2/18 — Installing Essential Packages"
    apt install -y software-properties-common ca-certificates lsb-release apt-transport-https \
        curl wget git zip unzip ufw
    complete_step 2
fi

# ============================================================
# Step 3: Nginx Install
# ============================================================
if should_run 3; then
    print_header "Step 3/18 — Installing Nginx"
    apt install -y nginx
    systemctl enable nginx
    systemctl start nginx
    complete_step 3
fi

# ============================================================
# Step 4: Firewall
# ============================================================
if should_run 4; then
    print_header "Step 4/18 — Configuring Firewall"
    ufw allow OpenSSH
    ufw allow 'Nginx Full'
    ufw --force enable
    complete_step 4
fi

# ============================================================
# Step 5: SSH Key for GitHub
# ============================================================
if should_run 5; then
    print_header "Step 5/18 — Setting Up SSH Key for GitHub"

    SSH_KEY_PATH="/root/.ssh/id_ed25519"

    if [ -f "$SSH_KEY_PATH" ]; then
        print_warning "SSH key already exists at $SSH_KEY_PATH"
        ask_yes_no "Generate a new SSH key anyway?" "n" REGEN_SSH
        if [ "$REGEN_SSH" = "true" ]; then
            ssh-keygen -t ed25519 -C "server@${DOMAIN}" -f "$SSH_KEY_PATH" -N ""
            print_success "New SSH key generated."
        fi
    else
        ssh-keygen -t ed25519 -C "server@${DOMAIN}" -f "$SSH_KEY_PATH" -N ""
        print_success "SSH key generated."
    fi

    eval "$(ssh-agent -s)" >/dev/null 2>&1
    ssh-add "$SSH_KEY_PATH" 2>/dev/null
    ssh-keyscan -t ed25519 github.com >> /root/.ssh/known_hosts 2>/dev/null

    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  Add this SSH key to your GitHub account${NC}"
    echo -e "${CYAN}  (Settings > SSH Keys > New SSH Key)${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    cat "${SSH_KEY_PATH}.pub"
    echo ""
    echo -e "${YELLOW}After adding the key to GitHub, press ENTER to continue...${NC}"
    read -r

    print_warning "Testing GitHub SSH connection..."
    if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
        print_success "GitHub SSH connection successful."
    else
        print_warning "Could not verify GitHub connection. The clone might still work."
        ask_yes_no "Continue anyway?" "y" CONTINUE_AFTER_SSH
        if [ "$CONTINUE_AFTER_SSH" = "false" ]; then exit 1; fi
    fi

    complete_step 5
fi

# ============================================================
# Step 6: PHP
# ============================================================
if should_run 6; then
    print_header "Step 6/18 — Installing PHP $PHP_VERSION"

    LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
    apt update

    apt install -y \
        php${PHP_VERSION}-common \
        php${PHP_VERSION}-fpm \
        php${PHP_VERSION}-xml \
        php${PHP_VERSION}-bcmath \
        php${PHP_VERSION}-mbstring \
        php${PHP_VERSION}-zip \
        php${PHP_VERSION}-curl \
        php${PHP_VERSION}-gd \
        php${PHP_VERSION}-intl \
        php${PHP_VERSION}-imagick \
        php${PHP_VERSION}-redis

    if [ "$DB_TYPE" = "mysql" ]; then
        apt install -y php${PHP_VERSION}-mysql
    else
        apt install -y php${PHP_VERSION}-pgsql
    fi

    complete_step 6
fi

# ============================================================
# Step 7: Composer
# ============================================================
if should_run 7; then
    print_header "Step 7/18 — Installing Composer"
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/bin --filename=composer
    print_success "Composer installed: $(composer --version)"
    complete_step 7
fi

# ============================================================
# Step 8: Database
# ============================================================
if should_run 8; then
    print_header "Step 8/18 — Installing $DB_TYPE"

    if [ "$DB_TYPE" = "mysql" ]; then
        apt install -y mysql-server
        systemctl enable mysql
        systemctl start mysql

        if [ "$DB_REMOTE_ACCESS" = "true" ]; then
            DB_HOST_SPEC="%"
        else
            DB_HOST_SPEC="localhost"
        fi

        mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'${DB_HOST_SPEC}' IDENTIFIED WITH mysql_native_password BY '${DB_PASS}';"
        mysql -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;"
        mysql -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'${DB_HOST_SPEC}';"
        mysql -e "FLUSH PRIVILEGES;"

        if [ "$DB_REMOTE_ACCESS" = "true" ]; then
            MYSQL_CNF=$(find /etc/mysql -name "mysqld.cnf" | head -1)
            if [ -n "$MYSQL_CNF" ]; then
                sed -i 's/^bind-address\s*=.*/bind-address = 0.0.0.0/' "$MYSQL_CNF"
                systemctl restart mysql
            fi
            ufw allow 3306/tcp
            print_success "MySQL remote access enabled (port 3306)."
        fi

        print_success "MySQL installed. User and database created."
    else
        apt install -y postgresql postgresql-contrib
        systemctl enable postgresql
        systemctl start postgresql

        sudo -u postgres psql -c "DO \$\$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='${DB_USER}') THEN CREATE ROLE ${DB_USER} WITH LOGIN PASSWORD '${DB_PASS}'; END IF; END \$\$;"
        sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};" 2>/dev/null || print_warning "Database '${DB_NAME}' already exists."
        sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};"

        PG_HBA=$(find /etc/postgresql -name pg_hba.conf | head -1)
        PG_CONF=$(find /etc/postgresql -name postgresql.conf | head -1)

        if [ -n "$PG_HBA" ]; then
            if [ "$DB_REMOTE_ACCESS" = "true" ]; then
                if ! grep -q "host.*${DB_NAME}.*${DB_USER}.*0.0.0.0/0" "$PG_HBA"; then
                    echo "host    ${DB_NAME}    ${DB_USER}    0.0.0.0/0    md5" >> "$PG_HBA"
                fi
                if [ -n "$PG_CONF" ]; then
                    sed -i "s/^#\?listen_addresses\s*=.*/listen_addresses = '*'/" "$PG_CONF"
                fi
                ufw allow 5432/tcp
                print_success "PostgreSQL remote access enabled (port 5432)."
            else
                if ! grep -q "host.*${DB_NAME}.*${DB_USER}" "$PG_HBA"; then
                    sed -i "/^# IPv4 local connections/a host    ${DB_NAME}    ${DB_USER}    127.0.0.1/32    md5" "$PG_HBA"
                fi
            fi
            systemctl restart postgresql
        fi

        print_success "PostgreSQL installed. User and database created."
    fi

    complete_step 8
fi

# ============================================================
# Step 9: Redis
# ============================================================
if should_run 9; then
    if [ "$SETUP_REDIS" = "true" ]; then
        print_header "Step 9/18 — Installing Redis"
        apt install -y redis-server

        sed -i 's/^supervised no/supervised systemd/' /etc/redis/redis.conf
        if ! grep -q "^supervised systemd" /etc/redis/redis.conf; then
            sed -i '/^# supervised/a supervised systemd' /etc/redis/redis.conf
        fi

        systemctl enable redis-server
        systemctl restart redis-server
        print_success "Redis installed and configured."
    else
        print_header "Step 9/18 — Skipping Redis (not selected)"
    fi
    complete_step 9
fi

# ============================================================
# Step 10: Clone Project
# ============================================================
if should_run 10; then
    print_header "Step 10/18 — Cloning Project"

    mkdir -p "$(dirname "$PROJECT_PATH")"

    if [ -d "$PROJECT_PATH" ]; then
        print_warning "Directory already exists: $PROJECT_PATH"
        ask_yes_no "Delete and re-clone?" "n" RECLONE
        if [ "$RECLONE" = "true" ]; then
            rm -rf "$PROJECT_PATH"
            git clone -b "$GIT_BRANCH" "$GIT_REPO" "$PROJECT_PATH"
        else
            print_warning "Keeping existing directory. Running git pull..."
            cd "$PROJECT_PATH" && git pull origin "$GIT_BRANCH"
        fi
    else
        git clone -b "$GIT_BRANCH" "$GIT_REPO" "$PROJECT_PATH"
    fi

    print_success "Project cloned: $PROJECT_PATH"
    complete_step 10
fi

# ============================================================
# Step 11: .env File
# ============================================================
if should_run 11; then
    print_header "Step 11/18 — Creating .env File"

    if [ "$DB_TYPE" = "mysql" ]; then
        DB_CONNECTION="mysql"
        DB_PORT="3306"
    else
        DB_CONNECTION="pgsql"
        DB_PORT="5432"
    fi

    APP_KEY_VALUE=$(php ${PROJECT_PATH}/artisan key:generate --show 2>/dev/null || echo "base64:$(openssl rand -base64 32)")

    cat > "${PROJECT_PATH}/.env" <<ENVEOF
APP_NAME="${APP_NAME}"
APP_ENV=production
APP_KEY=${APP_KEY_VALUE}
APP_DEBUG=false
APP_URL=https://${DOMAIN}

LOG_CHANNEL=stack
LOG_LEVEL=error

DB_CONNECTION=${DB_CONNECTION}
DB_HOST=127.0.0.1
DB_PORT=${DB_PORT}
DB_DATABASE=${DB_NAME}
DB_USERNAME=${DB_USER}
DB_PASSWORD=${DB_PASS}

BROADCAST_DRIVER=log
CACHE_DRIVER=redis
FILESYSTEM_DISK=local
QUEUE_CONNECTION=redis
SESSION_DRIVER=redis
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

    print_success ".env file created: ${PROJECT_PATH}/.env"
    complete_step 11
fi

# ============================================================
# Step 12: Composer Install
# ============================================================
if should_run 12; then
    print_header "Step 12/18 — Installing Composer Dependencies"
    cd "$PROJECT_PATH"
    composer install --no-dev --optimize-autoloader
    complete_step 12
fi

# ============================================================
# Step 13: Laravel Cache & Migrate
# ============================================================
if should_run 13; then
    print_header "Step 13/18 — Laravel Cache & Migrate"
    cd "$PROJECT_PATH"
    php artisan config:cache
    php artisan route:cache
    php artisan view:cache
    php artisan migrate --force
    complete_step 13
fi

# ============================================================
# Step 14: File Permissions
# ============================================================
if should_run 14; then
    print_header "Step 14/18 — Setting File Permissions"
    chown -R www-data:www-data "$PROJECT_PATH"
    chmod -R 775 "$PROJECT_PATH/storage"
    chmod -R 775 "$PROJECT_PATH/bootstrap/cache"
    complete_step 14
fi

# ============================================================
# Step 15: Nginx Virtual Host
# ============================================================
if should_run 15; then
    print_header "Step 15/18 — Configuring Nginx Virtual Host"

    cat > "/etc/nginx/sites-available/${DOMAIN}" <<NGINXEOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};
    root ${PROJECT_PATH}/public;

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
    complete_step 15
fi

# ============================================================
# Step 16: SSL
# ============================================================
if should_run 16; then
    if [ "$SETUP_SSL" = "true" ]; then
        print_header "Step 16/18 — Installing SSL Certificate"
        apt install -y certbot python3-certbot-nginx
        certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$SSL_EMAIL" --redirect
        print_success "SSL certificate installed."

        if ! crontab -l 2>/dev/null | grep -q "certbot renew"; then
            (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet && systemctl reload nginx") | crontab -
            print_success "SSL auto-renewal cron added."
        fi
    else
        print_header "Step 16/18 — Skipping SSL (not selected)"
    fi
    complete_step 16
fi

# ============================================================
# Step 17: Supervisor
# ============================================================
if should_run 17; then
    print_header "Step 17/18 — Installing Supervisor"
    apt install -y supervisor

    cat > "/etc/supervisor/conf.d/laravel-worker.conf" <<SUPEOF
[program:laravel-worker]
process_name=%(program_name)s_%(process_num)02d
command=php ${PROJECT_PATH}/artisan queue:work redis --sleep=3 --tries=3 --max-time=3600
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

    supervisorctl reread
    supervisorctl update
    supervisorctl start "laravel-worker:*" 2>/dev/null || true
    print_success "Supervisor configured (${WORKER_COUNT} queue workers)."
    complete_step 17
fi

# ============================================================
# Step 18: Laravel Scheduler Cron
# ============================================================
if should_run 18; then
    print_header "Step 18/18 — Adding Laravel Scheduler Cron"
    CRON_CMD="* * * * * cd ${PROJECT_PATH} && php artisan schedule:run >> /dev/null 2>&1"
    if ! crontab -u www-data -l 2>/dev/null | grep -q "schedule:run"; then
        (crontab -u www-data -l 2>/dev/null; echo "$CRON_CMD") | crontab -u www-data -
        print_success "Laravel scheduler cron added."
    else
        print_warning "Scheduler cron already exists."
    fi
    complete_step 18
fi

# ============================================================
# Done
# ============================================================
print_header "Installation Complete!"

echo -e "${GREEN}Summary:${NC}"
echo -e "  Domain:        https://${DOMAIN}"
echo -e "  Project Dir:   ${PROJECT_PATH}"
echo -e "  Database:      ${DB_TYPE} (${DB_NAME})"
echo -e "  PHP:           ${PHP_VERSION}"
echo -e "  SSL:           ${SETUP_SSL}"
echo -e "  Redis:         ${SETUP_REDIS}"
echo -e "  Workers:       ${WORKER_COUNT}"
echo ""
echo -e "${YELLOW}TODO:${NC}"
echo -e "  1. Review ${PROJECT_PATH}/.env (fill in Mail, AWS credentials)"
echo -e "  2. Check logs: tail -f ${PROJECT_PATH}/storage/logs/laravel.log"
echo -e "  3. Monitor workers: supervisorctl status"
echo ""

rm -f "$CONFIG_FILE"
print_success "Laravel Deployr finished successfully!"
