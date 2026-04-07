#!/usr/bin/env bats
# Unit tests for lib/core.sh

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"

setup() {
    # Each test gets a temp config file so we don't touch real /root/
    export CONFIG_FILE
    CONFIG_FILE="$(mktemp)"
    export CURRENT_STEP=0
    export PROVISIONED=false
    # Silence interactive prompts in all tests
    export NON_INTERACTIVE=true

    # shellcheck source=../../lib/core.sh
    source "${REPO_ROOT}/lib/core.sh"
}

teardown() {
    rm -f "$CONFIG_FILE"
}

# ── print helpers ────────────────────────────────────────────────────────────

@test "print_success outputs [OK] and message" {
    run print_success "everything works"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[OK]"* ]]
    [[ "$output" == *"everything works"* ]]
}

@test "print_warning outputs [!] and message" {
    run print_warning "watch out"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[!]"* ]]
    [[ "$output" == *"watch out"* ]]
}

@test "print_error outputs [ERROR] and message to stderr" {
    run print_error "something broke"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[ERROR]"* ]]
    [[ "$output" == *"something broke"* ]]
}

# ── should_run ───────────────────────────────────────────────────────────────

@test "should_run returns true when CURRENT_STEP < target" {
    CURRENT_STEP=0
    run should_run 1
    [ "$status" -eq 0 ]
}

@test "should_run returns false when CURRENT_STEP == target" {
    CURRENT_STEP=5
    run should_run 5
    [ "$status" -ne 0 ]
}

@test "should_run returns false when CURRENT_STEP > target" {
    CURRENT_STEP=7
    run should_run 3
    [ "$status" -ne 0 ]
}

# ── complete_step ────────────────────────────────────────────────────────────

@test "complete_step increments CURRENT_STEP and writes config" {
    APP_NAME="TestApp" DOMAIN="example.com" DB_TYPE="postgresql"
    DB_NAME="db" DB_USER="u" DB_PASS="p" DB_REMOTE_ACCESS="false"
    PHP_VERSION="8.4" BASE_PATH="/var/www/test"
    GIT_REPO="git@github.com:x/y.git" GIT_BRANCH="main"
    WORKER_COUNT="4" SETUP_REDIS="true"
    REDIS_HOST="127.0.0.1" REDIS_PORT="6379"
    SETUP_SSL="false" SSL_EMAIL=""

    complete_step 3

    [ "$CURRENT_STEP" -eq 3 ]
    grep -q "COMPLETED_STEP=3" "$CONFIG_FILE"
}

# ── ask (non-interactive mode) ───────────────────────────────────────────────

@test "ask uses default when variable is empty in non-interactive mode" {
    MY_VAR=""
    ask "Some prompt" "default_val" MY_VAR
    [ "$MY_VAR" = "default_val" ]
}

@test "ask preserves existing value in non-interactive mode" {
    MY_VAR="already_set"
    ask "Some prompt" "default_val" MY_VAR
    [ "$MY_VAR" = "already_set" ]
}

@test "ask exits 1 when no value and no default in non-interactive mode" {
    REQUIRED_VAR=""
    run bash -c "
        source '${REPO_ROOT}/lib/core.sh'
        CONFIG_FILE='$(mktemp)'
        NON_INTERACTIVE=true
        REQUIRED_VAR=''
        ask 'Something required' '' REQUIRED_VAR
    "
    [ "$status" -ne 0 ]
}

# ── ask_yes_no (non-interactive mode) ────────────────────────────────────────

@test "ask_yes_no defaults to true when default is y and var is unset" {
    FLAG=""
    ask_yes_no "Enable?" "y" FLAG
    [ "$FLAG" = "true" ]
}

@test "ask_yes_no defaults to false when default is n and var is unset" {
    FLAG=""
    ask_yes_no "Enable?" "n" FLAG
    [ "$FLAG" = "false" ]
}

@test "ask_yes_no preserves pre-set value in non-interactive mode" {
    FLAG="true"
    ask_yes_no "Enable?" "n" FLAG
    [ "$FLAG" = "true" ]
}

# ── save_config ───────────────────────────────────────────────────────────────

@test "save_config creates a readable config file" {
    APP_NAME="MyApp" DOMAIN="myapp.com" SETUP_SSL="true" SSL_EMAIL="a@b.com"
    DB_TYPE="mysql" DB_NAME="mydb" DB_USER="user" DB_PASS="pass"
    DB_REMOTE_ACCESS="false" PHP_VERSION="8.3" BASE_PATH="/var/www/myapp"
    GIT_REPO="git@github.com:a/b.git" GIT_BRANCH="main"
    WORKER_COUNT="4" SETUP_REDIS="false"
    REDIS_HOST="127.0.0.1" REDIS_PORT="6379"

    save_config

    [ -f "$CONFIG_FILE" ]
    grep -q 'APP_NAME="MyApp"'   "$CONFIG_FILE"
    grep -q 'DOMAIN="myapp.com"' "$CONFIG_FILE"
    grep -q 'DB_TYPE="mysql"'    "$CONFIG_FILE"
}

@test "save_config sets mode 600 on the config file" {
    APP_NAME="" DOMAIN="" SETUP_SSL="false" SSL_EMAIL=""
    DB_TYPE="postgresql" DB_NAME="" DB_USER="" DB_PASS=""
    DB_REMOTE_ACCESS="false" PHP_VERSION="8.4" BASE_PATH=""
    GIT_REPO="" GIT_BRANCH="main" WORKER_COUNT="8"
    SETUP_REDIS="true" REDIS_HOST="127.0.0.1" REDIS_PORT="6379"

    save_config

    local perms
    perms=$(stat -c "%a" "$CONFIG_FILE" 2>/dev/null || stat -f "%Lp" "$CONFIG_FILE")
    [ "$perms" = "600" ]
}
