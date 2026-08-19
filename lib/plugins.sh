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
# Run Assetfinder for passive subdomain enumeration
run_assetfinder() {

    local domain="$1"
    local output_file="$2"

    log_info "Running Assetfinder on $domain"

    if ! command_exists assetfinder; then
        log_error "Assetfinder is not installed."
        return 1
    fi

    if assetfinder --subs-only "$domain" | sort -u > "$output_file"; then
        local count

        count=$(wc -l < "$output_file")

        log_success "Assetfinder completed: $count subdomains found"

        return 0
    else
        log_error "Assetfinder failed for $domain"
        return 1
    fi
}
merge_subdomains() {

    local subdomain_dir="$1"
    local output_file="${subdomain_dir}/all.txt"

    log_info "Merging subdomain results"

    cat "$subdomain_dir/subfinder.txt" \
        "$subdomain_dir/assetfinder.txt" 2>/dev/null |
        sed '/^$/d' |
        sort -u > "$output_file"

    local count
    count=$(wc -l < "$output_file")

    log_success "Unique subdomains: $count"

    return 0
}