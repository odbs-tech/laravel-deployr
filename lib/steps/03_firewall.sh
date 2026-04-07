#!/bin/bash
# Step 4: UFW firewall

step_firewall() {
    print_header "Step 4 — Configuring Firewall (UFW)"
    ufw allow OpenSSH
    ufw allow 'Nginx Full'
    ufw --force enable
    complete_step 4
}
