#!/bin/bash
# install.sh — Install deployr to /opt/deployr and symlink to /usr/local/bin

INSTALL_DIR="/opt/deployr"
BIN_LINK="/usr/local/bin/deployr"

install_command() {
    check_root

    print_header "Installing Laravel Deployr"

    # Verify source is a valid deployr tree
    if [ ! -f "${DEPLOYR_ROOT}/deployr" ] || [ ! -d "${DEPLOYR_ROOT}/lib" ]; then
        print_error "Cannot find deployr source at ${DEPLOYR_ROOT}."
        exit 1
    fi

    # Warn if already installed
    if [ -d "$INSTALL_DIR" ]; then
        print_warning "An existing installation was found at $INSTALL_DIR."
        ask_yes_no "Overwrite it?" "y" OVERWRITE
        [ "$OVERWRITE" = "false" ] && { echo "Install cancelled."; exit 0; }
        rm -rf "$INSTALL_DIR"
    fi

    print_info "Copying files to ${INSTALL_DIR}..."
    mkdir -p "$INSTALL_DIR"

    # Copy the entrypoint and lib tree
    cp "${DEPLOYR_ROOT}/deployr" "${INSTALL_DIR}/deployr"
    cp -r "${DEPLOYR_ROOT}/lib"  "${INSTALL_DIR}/lib"

    chmod +x "${INSTALL_DIR}/deployr"
    chmod -R 755 "${INSTALL_DIR}/lib"

    # Create (or update) the symlink in /usr/local/bin
    ln -sfn "${INSTALL_DIR}/deployr" "$BIN_LINK"
    print_success "Symlink created: ${BIN_LINK} → ${INSTALL_DIR}/deployr"

    # Smoke-test
    if "$BIN_LINK" --help >/dev/null 2>&1; then
        print_success "deployr is working correctly."
    else
        print_warning "Smoke-test failed. Check ${INSTALL_DIR}/deployr manually."
    fi

    print_success "Installation complete!"
    echo ""
    echo -e "  Run from anywhere:  ${BOLD}sudo deployr deploy --app <name>${NC}"
    echo -e "  Installed at:       ${INSTALL_DIR}"
    echo -e "  Symlink:            ${BIN_LINK}"
    echo ""
}
