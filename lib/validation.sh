#!/usr/bin/env bash

# ============================================
# Recon Framework - Validation Library
# ============================================

# Validate target domain
validate_domain() {

    local domain="$1"

    if [[ -z "$domain" ]]; then
        log_error "Target domain cannot be empty."
        return 1
    fi

    # Basic domain validation
    if [[ ! "$domain" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
        log_error "Invalid domain: $domain"
        return 1
    fi

    return 0
}