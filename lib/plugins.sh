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
# Resolve discovered subdomains using DNSX
run_dnsx() {

    local input_file="$1"
    local output_file="$2"

    log_info "Running DNSX"

    if ! command_exists dnsx; then
        log_error "DNSX is not installed."
        return 1
    fi

    if [[ ! -f "$input_file" ]]; then
        log_error "Subdomain input file not found: $input_file"
        return 1
    fi

    if dnsx -l "$input_file" -silent -o "$output_file"; then
        local count

        count=$(wc -l < "$output_file")

        log_success "DNSX completed: $count resolved hosts"

        return 0
    else
        log_error "DNSX failed"
        return 1
    fi
}
# Probe live HTTP/HTTPS services using HTTPX
run_httpx() {

    local input_file="$1"
    local output_file="$2"

    log_info "Running HTTPX"

    if ! command_exists httpx; then
        log_error "HTTPX is not installed."
        return 1
    fi

    if [[ ! -f "$input_file" ]]; then
        log_error "DNS input file not found: $input_file"
        return 1
    fi

    if httpx \
        -l "$input_file" \
        -silent \
        -status-code \
        -title \
        -tech-detect \
        -server \
        -o "$output_file"; then

        local count
        count=$(wc -l < "$output_file")

        log_success "HTTPX completed: $count live HTTP services found"

        return 0
    else
        log_error "HTTPX failed"
        return 1
    fi
}
# Discover open ports using Naabu
run_naabu() {

    local input_file="$1"
    local output_file="$2"

    log_info "Running Naabu"

    if ! command_exists naabu; then
        log_error "Naabu is not installed."
        return 1
    fi

    if [[ ! -f "$input_file" ]]; then
        log_error "DNS input file not found: $input_file"
        return 1
    fi

    if naabu \
        -list "$input_file" \
        -silent \
        -o "$output_file"; then

        local count
        count=$(wc -l < "$output_file")

        log_success "Naabu completed: $count open ports found"

        return 0
    else
        log_error "Naabu failed"
        return 1
    fi
}