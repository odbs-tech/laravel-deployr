#!/bin/bash
# core.sh — Shared utilities for Laravel Deployr

DEPLOYR_VERSION="2.0.0"
CONFIG_FILE="/root/.laravel-deployr.conf"
CURRENT_STEP=0
PROVISIONED="${PROVISIONED:-false}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

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

save_config() {
    cat > "$CONFIG_FILE" <<CFGEOF
COMPLETED_STEP=${CURRENT_STEP}
PROVISIONED=${PROVISIONED:-false}
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
SETUP_REDIS="${SETUP_REDIS:-true}"
REDIS_HOST="${REDIS_HOST:-127.0.0.1}"
REDIS_PORT="${REDIS_PORT:-6379}"
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
    "Nginx"
    "Firewall"
    "SSH Key"
    "PHP"
    "Composer"
    "Database"
    "Redis"
    "Nginx Virtual Host"
    "SSL Certificate"
    "Supervisor"
    "Scheduler Cron"
)
