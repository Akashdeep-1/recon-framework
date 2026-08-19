#!/usr/bin/env bash

# ============================================
# Recon Framework - Plugin Library
# ============================================

# Run Subfinder for passive subdomain enumeration
run_subfinder() {

    local domain="$1"
    local output_file="$2"

    log_info "Running Subfinder on $domain"

    if ! command_exists subfinder; then
        log_error "Subfinder is not installed."
        return 1
    fi

    if subfinder -d "$domain" -silent -o "$output_file"; then
        local count

        count=$(wc -l < "$output_file")

        log_success "Subfinder completed: $count subdomains found"

        return 0
    else
        log_error "Subfinder failed for $domain"
        return 1
    fi
}