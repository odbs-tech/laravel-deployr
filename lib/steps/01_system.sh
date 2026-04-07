#!/bin/bash
# Step 1: System update | Step 2: Essential packages

step_system_update() {
    print_header "Step 1 — Updating System"
    apt-get update -qq && apt-get upgrade -y
    complete_step 1
}

step_essential_packages() {
    print_header "Step 2 — Installing Essential Packages"
    apt-get install -y \
        software-properties-common \
        ca-certificates \
        lsb-release \
        apt-transport-https \
        curl \
        wget \
        git \
        zip \
        unzip \
        ufw \
        gnupg2
    complete_step 2
}
