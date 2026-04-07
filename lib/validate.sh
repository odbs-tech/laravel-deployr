#!/bin/bash
# validate.sh — Pre-flight validation checks

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root. Use: sudo deployr <command>"
        exit 1
    fi
}

detect_os() {
    if [ -f /etc/os-release ]; then
        # shellcheck source=/dev/null
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
        print_warning "Optimized for Ubuntu/Debian. Current OS: $OS_NAME"
        ask_yes_no "Continue anyway?" "n" CONTINUE_UNSUPPORTED
        [ "$CONTINUE_UNSUPPORTED" = "false" ] && exit 1
    fi
}

check_disk_space() {
    local required_mb="${1:-2048}"
    local available_mb
    available_mb=$(df / --output=avail -BM | tail -1 | tr -d 'M ')
    if [ "$available_mb" -lt "$required_mb" ]; then
        print_error "Insufficient disk space. Required: ${required_mb}MB, Available: ${available_mb}MB"
        exit 1
    fi
    print_success "Disk space OK (${available_mb}MB available)"
}

check_dns() {
    local domain="$1"
    if command -v dig &>/dev/null; then
        local resolved
        resolved=$(dig +short "$domain" A 2>/dev/null | head -1)
        if [ -n "$resolved" ]; then
            print_success "DNS: $domain → $resolved"
        else
            print_warning "DNS: Could not resolve $domain. SSL setup may fail."
        fi
    elif command -v host &>/dev/null; then
        if host "$domain" &>/dev/null; then
            print_success "DNS: $domain resolves OK"
        else
            print_warning "DNS: Could not resolve $domain. SSL setup may fail."
        fi
    fi
}
