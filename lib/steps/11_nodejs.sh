#!/bin/bash
# Step 10: Node.js installation via NodeSource (optional)

step_nodejs() {
    if [ "${SETUP_NODEJS:-false}" = "true" ]; then
        print_header "Step 10 — Installing Node.js ${NODE_VERSION:-20}"

        local node_ver="${NODE_VERSION:-20}"

        # Add NodeSource repository
        curl -fsSL "https://deb.nodesource.com/setup_${node_ver}.x" | bash -

        apt-get install -y nodejs

        # Verify
        local installed_node installed_npm
        installed_node=$(node --version 2>/dev/null || echo "unknown")
        installed_npm=$(npm --version 2>/dev/null || echo "unknown")
        print_success "Node.js ${installed_node} / npm ${installed_npm} installed."
    else
        print_info "Step 10 — Skipping Node.js (not selected)"
    fi

    complete_step 10
}
