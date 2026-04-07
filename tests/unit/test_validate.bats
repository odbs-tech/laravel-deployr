#!/usr/bin/env bats
# Unit tests for lib/validate.sh

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"

setup() {
    export CONFIG_FILE
    CONFIG_FILE="$(mktemp)"
    export NON_INTERACTIVE=true
    export CURRENT_STEP=0

    # shellcheck source=../../lib/core.sh
    source "${REPO_ROOT}/lib/core.sh"
    # shellcheck source=../../lib/validate.sh
    source "${REPO_ROOT}/lib/validate.sh"
}

teardown() {
    rm -f "$CONFIG_FILE"
}

# ── check_root ───────────────────────────────────────────────────────────────

@test "check_root fails when EUID is non-zero" {
    run bash -c "
        source '${REPO_ROOT}/lib/core.sh'
        source '${REPO_ROOT}/lib/validate.sh'
        EUID=1000
        check_root
    "
    [ "$status" -ne 0 ]
}

@test "check_root passes when EUID is 0" {
    # We can only simulate this safely; skip if not root
    if [ "$EUID" -ne 0 ]; then
        skip "Must be root to test check_root success path"
    fi
    run check_root
    [ "$status" -eq 0 ]
}

# ── check_disk_space ─────────────────────────────────────────────────────────

@test "check_disk_space passes with a 1 MB threshold" {
    run check_disk_space 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"Disk space OK"* ]]
}

@test "check_disk_space fails with an impossibly large threshold" {
    run check_disk_space 999999999
    [ "$status" -ne 0 ]
    [[ "$output" == *"Insufficient"* ]]
}

# ── check_dns ────────────────────────────────────────────────────────────────

@test "check_dns does not exit on unresolvable domain" {
    # check_dns is informational only — should never exit 1
    run check_dns "this-domain-definitely-does-not-exist-xyz.invalid"
    [ "$status" -eq 0 ]
}

@test "check_dns succeeds for a real domain" {
    if ! command -v dig &>/dev/null && ! command -v host &>/dev/null; then
        skip "dig/host not available"
    fi
    run check_dns "github.com"
    [ "$status" -eq 0 ]
}
