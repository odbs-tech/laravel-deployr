#!/bin/bash
# core.sh — Shared utilities for Laravel Deployr

DEPLOYR_VERSION="2.0.0"

# ─── Config paths ─────────────────────────────────────────────────────────────
DEPLOYR_CONF_DIR="/root/.laravel-deployr"
SERVER_CONF="${DEPLOYR_CONF_DIR}/.server.conf"
# CONFIG_FILE is set dynamically once APP_SLUG is known (see resolve_config_file)
CONFIG_FILE=""

CURRENT_STEP=0
APP_SLUG="${APP_SLUG:-}"

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ─── Banner & Headers ─────────────────────────────────────────────────────────

print_banner() {
    echo -e "${CYAN}"
    echo '  _                          _   ____             _                 '
    echo ' | |    __ _ _ __ __ ___   _| | |  _ \  ___ _ __ | | ___  _   _ _ __ '
    echo ' | |   / _` | `__/ _` \ \ / / | | | | |/ _ \ `_ \| |/ _ \| | | | `__|'
    echo ' | |__| (_| | | | (_| |\ V /| | | |_| |  __/ |_) | | (_) | |_| | |   '
    echo ' |_____\__,_|_|  \__,_| \_/ |_| |____/ \___| .__/|_|\___/ \__, |_|   '
    echo '                                             |_|            |___/      '
    echo -e "${NC}"
    echo -e "${BOLD}Laravel Deployr v${DEPLOYR_VERSION}${NC}"
    echo ""
}

print_header() {
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}========================================${NC}\n"
}

print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }
print_info()    { echo -e "${CYAN}[>]${NC} $1"; }

# ─── App slug helpers ─────────────────────────────────────────────────────────

# Convert a string to a safe filename slug (lowercase, hyphens)
slugify() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//'
}

# Set CONFIG_FILE based on APP_SLUG; create conf dir if needed
resolve_config_file() {
    mkdir -p "$DEPLOYR_CONF_DIR"
    chmod 700 "$DEPLOYR_CONF_DIR"
    if [ -z "$APP_SLUG" ]; then
        print_error "APP_SLUG is not set. Use --app <name> or let deploy prompt set it."
        exit 1
    fi
    CONFIG_FILE="${DEPLOYR_CONF_DIR}/${APP_SLUG}.conf"
    export CONFIG_FILE
}

# List all deployed app slugs (conf files in the conf dir)
list_app_slugs() {
    find "$DEPLOYR_CONF_DIR" -maxdepth 1 -name "*.conf" 2>/dev/null \
        | sed 's|.*/||;s|\.conf$||' | sort
}

# Auto-select app slug when --app is not given:
#   - 0 apps → return empty (new deploy)
#   - 1 app  → auto-select it
#   - 2+ apps → error: require --app
auto_select_app() {
    local slugs
    mapfile -t slugs < <(list_app_slugs)
    local count="${#slugs[@]}"

    if [ "$count" -eq 0 ]; then
        return  # fresh server, APP_SLUG stays empty until _ask_configuration sets it
    elif [ "$count" -eq 1 ]; then
        APP_SLUG="${slugs[0]}"
        export APP_SLUG
    else
        print_error "Multiple apps found. Specify which one with --app <name>."
        echo ""
        echo "Available apps:"
        for s in "${slugs[@]}"; do echo "  - $s"; done
        echo ""
        exit 1
    fi
}

# ─── Input helpers ────────────────────────────────────────────────────────────

ask() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"

    if [ "${NON_INTERACTIVE:-false}" = "true" ]; then
        local current_val
        current_val="$(eval echo "\"\$$var_name\"")"
        if [ -z "$current_val" ] && [ -n "$default" ]; then
            eval "$var_name=\"$default\""
        elif [ -z "$current_val" ]; then
            print_error "Required variable \$$var_name is not set (non-interactive mode)."
            exit 1
        fi
        return
    fi

    local input
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

    if [ "${NON_INTERACTIVE:-false}" = "true" ]; then
        local current_val
        current_val="$(eval echo "\"\$$var_name\"")"
        if [ -z "$current_val" ]; then
            print_error "Required secret \$$var_name is not set (non-interactive mode)."
            exit 1
        fi
        return
    fi

    local input
    read -srp "$(echo -e "${YELLOW}$prompt: ${NC}")" input
    echo ""
    eval "$var_name=\"$input\""
}

ask_yes_no() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"

    if [ "${NON_INTERACTIVE:-false}" = "true" ]; then
        local current_val
        current_val="$(eval echo "\"\$$var_name\"")"
        if [ -z "$current_val" ]; then
            [ "$default" = "y" ] && eval "$var_name=true" || eval "$var_name=false"
        fi
        return
    fi

    local input
    if [ "$default" = "y" ]; then
        read -rp "$(echo -e "${YELLOW}$prompt ${NC}[${GREEN}Y/n${NC}]: ")" input
        input="${input:-y}"
    else
        read -rp "$(echo -e "${YELLOW}$prompt ${NC}[${GREEN}y/N${NC}]: ")" input
        input="${input:-n}"
    fi

    case "$input" in
        [yY]) eval "$var_name=true" ;;
        *)    eval "$var_name=false" ;;
    esac
}

# ─── Config persistence ───────────────────────────────────────────────────────

# Server-level config: provisioning state, installed PHP versions, Redis, Node.js
# PHP_VERSION is intentionally NOT stored here — each app keeps its own version.
save_server_config() {
    mkdir -p "$DEPLOYR_CONF_DIR"
    cat > "$SERVER_CONF" <<CFGEOF
SERVER_PROVISIONED=${SERVER_PROVISIONED:-false}
INSTALLED_PHP_VERSIONS="${INSTALLED_PHP_VERSIONS:-}"
SETUP_REDIS="${SETUP_REDIS:-true}"
REDIS_HOST="${REDIS_HOST:-127.0.0.1}"
REDIS_PORT="${REDIS_PORT:-6379}"
SETUP_NODEJS="${SETUP_NODEJS:-false}"
NODE_VERSION="${NODE_VERSION:-20}"
CFGEOF
    chmod 600 "$SERVER_CONF"
}

# Returns 0 (true) if the given PHP version is already installed on this server
php_version_is_installed() {
    local ver="$1"
    echo "${INSTALLED_PHP_VERSIONS:-}" | tr ' ' '\n' | grep -qx "$ver"
}

# Add a PHP version to the installed list and persist
register_php_version() {
    local ver="$1"
    if ! php_version_is_installed "$ver"; then
        INSTALLED_PHP_VERSIONS="${INSTALLED_PHP_VERSIONS:+${INSTALLED_PHP_VERSIONS} }${ver}"
        save_server_config
    fi
}

# App-level config: domain, git, database, PHP version, paths, deploy state
save_app_config() {
    [ -z "$CONFIG_FILE" ] && resolve_config_file
    cat > "$CONFIG_FILE" <<CFGEOF
COMPLETED_STEP=${CURRENT_STEP}
APP_SLUG="${APP_SLUG:-}"
APP_NAME="${APP_NAME:-}"
DOMAIN="${DOMAIN:-}"
SETUP_SSL="${SETUP_SSL:-false}"
SSL_EMAIL="${SSL_EMAIL:-}"
DB_TYPE="${DB_TYPE:-postgresql}"
DB_NAME="${DB_NAME:-}"
DB_USER="${DB_USER:-}"
DB_PASS="${DB_PASS:-}"
DB_REMOTE_ACCESS="${DB_REMOTE_ACCESS:-false}"
PHP_VERSION="${PHP_VERSION:-8.4}"
BASE_PATH="${BASE_PATH:-}"
GIT_REPO="${GIT_REPO:-}"
GIT_BRANCH="${GIT_BRANCH:-main}"
WORKER_COUNT="${WORKER_COUNT:-8}"
NPM_BUILD_CMD="${NPM_BUILD_CMD:-}"
CFGEOF
    chmod 600 "$CONFIG_FILE"
}

# Legacy alias used by step files via complete_step
save_config() {
    save_app_config
    save_server_config
}

complete_step() {
    CURRENT_STEP=$1
    save_app_config
    print_success "Step $1 completed."
}

should_run() {
    [ "$CURRENT_STEP" -lt "$1" ]
}

# ─── Step names ───────────────────────────────────────────────────────────────

STEP_NAMES=(
    ""
    "System Update"
    "Essential Packages"
    "Nginx"
    "Firewall"
    "SSH Key"
    "PHP + Opcache"
    "Composer"
    "Database"
    "Redis"
    "Node.js"
    "Nginx Virtual Host"
    "SSL Certificate"
    "Supervisor"
    "Scheduler Cron"
)
