#!/bin/bash
# Step 7: Composer global install

step_composer() {
    print_header "Step 7 — Installing Composer"

    curl -sS https://getcomposer.org/installer \
        | php -- --install-dir=/usr/local/bin --filename=composer

    print_success "Composer installed: $(composer --version)"
    complete_step 7
}
