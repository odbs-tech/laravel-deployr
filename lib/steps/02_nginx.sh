#!/bin/bash
# Step 3: Nginx install

step_nginx() {
    print_header "Step 3 — Installing Nginx"
    apt-get install -y nginx
    systemctl enable nginx
    systemctl start nginx
    complete_step 3
}
