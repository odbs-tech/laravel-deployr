#!/bin/bash
# Step 5: SSH key generation for Git deploy

step_ssh_key() {
    print_header "Step 5 — Setting Up SSH Deploy Key"

    local ssh_key_path="/root/.ssh/id_ed25519"

    if [ -f "$ssh_key_path" ]; then
        print_warning "SSH key already exists at $ssh_key_path"
        ask_yes_no "Generate a new SSH key anyway?" "n" REGEN_SSH
        if [ "$REGEN_SSH" = "true" ]; then
            ssh-keygen -t ed25519 -C "deployr@${DOMAIN}" -f "$ssh_key_path" -N ""
            print_success "New SSH key generated."
        fi
    else
        ssh-keygen -t ed25519 -C "deployr@${DOMAIN}" -f "$ssh_key_path" -N ""
        print_success "SSH key generated."
    fi

    eval "$(ssh-agent -s)" >/dev/null 2>&1
    ssh-add "$ssh_key_path" 2>/dev/null || true
    ssh-keyscan -t ed25519 github.com >> /root/.ssh/known_hosts 2>/dev/null

    if [ "${NON_INTERACTIVE:-false}" != "true" ]; then
        echo ""
        echo -e "${CYAN}Add this deploy key to your GitHub repository:${NC}"
        echo -e "${CYAN}(Repo Settings → Deploy keys → Add deploy key)${NC}"
        echo ""
        cat "${ssh_key_path}.pub"
        echo ""
        echo -e "${YELLOW}Press ENTER after adding the key to GitHub...${NC}"
        read -r
    fi

    if ssh -o BatchMode=yes -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
        print_success "GitHub SSH connection verified."
    else
        print_warning "Could not verify GitHub connection. Clone may still work."
        if [ "${NON_INTERACTIVE:-false}" != "true" ]; then
            ask_yes_no "Continue anyway?" "y" CONTINUE_AFTER_SSH
            [ "$CONTINUE_AFTER_SSH" = "false" ] && exit 1
        fi
    fi

    complete_step 5
}
