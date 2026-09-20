#!/usr/bin/env bash

# ============================================
# Recon Framework - Validation Library
# ============================================

# Sourcing guard & logger reference
VALIDATION_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v log_error >/dev/null 2>&1; then
    # shellcheck source=./logger.sh
    source "$VALIDATION_LIB_DIR/logger.sh"
fi

# Normalize a domain name:
# - trim leading/trailing whitespace
# - remove any trailing dot
# - convert to lowercase
normalize_domain() {
    local raw="$1"

    # Trim leading and trailing whitespace
    local cleaned="${raw#"${raw%%[![:space:]]*}"}"
    cleaned="${cleaned%"${cleaned##*[![:space:]]}"}"

    # Convert to lowercase
    cleaned="$(printf '%s' "$cleaned" | tr '[:upper:]' '[:lower:]')"

    # Strip any trailing dots (e.g. FQDN trailing dot)
    cleaned="${cleaned%.}"

    printf '%s' "$cleaned"
}

# Validate that a domain is well-formed
validate_domain() {
    local raw="$1"
    local domain
    domain="$(normalize_domain "$raw")"

    if [[ -z "$domain" ]]; then
        log_error "Target domain cannot be empty."
        return 1
    fi

    # Total length check: 1 to 253 characters
    local len="${#domain}"
    if (( len < 3 || len > 253 )); then
        log_error "Domain length invalid ($len chars): $domain"
        return 1
    fi

    # Reject consecutive dots or invalid characters
    # Allowed in hostnames: letters, numbers, hyphens, and underscores (e.g., DNS records like _dmarc)
    if [[ "$domain" == *..* || "$domain" =~ [^a-z0-9._-] ]]; then
        log_error "Domain contains invalid characters or consecutive dots: $domain"
        return 1
    fi

    # Domain must contain at least one dot separating labels
    if [[ "$domain" != *.* ]]; then
        log_error "Domain must contain at least one dot (domain + TLD): $domain"
        return 1
    fi

    # Validate individual labels
    local IFS='.'
    read -r -a labels <<< "$domain"
    local num_labels="${#labels[@]}"

    if (( num_labels < 2 )); then
        log_error "Domain must have at least two labels: $domain"
        return 1
    fi

    local i
    for (( i=0; i<num_labels; i++ )); do
        local label="${labels[i]}"
        local label_len="${#label}"

        # Each label must be 1 to 63 characters
        if (( label_len < 1 || label_len > 63 )); then
            log_error "Invalid label length '$label' in domain: $domain"
            return 1
        fi

        # Label cannot start or end with a hyphen
        if [[ "$label" == -* || "$label" == *- ]]; then
            log_error "Domain label cannot start or end with hyphen: '$label' in $domain"
            return 1
        fi
    done

    # Validate TLD (the last label) - must be alphabetic and at least 2 chars
    local tld="${labels[num_labels-1]}"
    if [[ ! "$tld" =~ ^[a-z]{2,}$ ]]; then
        log_error "Invalid Top-Level Domain (TLD) '$tld' in domain: $domain"
        return 1
    fi

    return 0
}

# Strict scope check: returns 0 if candidate is exactly target_domain or a subdomain of target_domain
# Explicitly prevents suffix attacks (e.g. evil-example.com matching example.com)
is_in_scope() {
    local candidate_raw="$1"
    local target_raw="$2"

    local candidate target
    candidate="$(normalize_domain "$candidate_raw")"
    target="$(normalize_domain "$target_raw")"

    # Reject empty or blank candidate/target
    if [[ -z "$candidate" || -z "$target" ]]; then
        return 1
    fi

    # Reject if candidate contains URL parts or ports
    if [[ "$candidate" == *:* || "$candidate" == */* || "$candidate" == *" "* ]]; then
        return 1
    fi

    # Exact match: candidate equals target
    if [[ "$candidate" == "$target" ]]; then
        return 0
    fi

    # Subdomain match: candidate must end with '.' + target
    # This prevents suffix collision tricks (e.g. "notexample.com" does NOT match ".example.com")
    local suffix=".${target}"
    if [[ "$candidate" == *"$suffix" ]]; then
        return 0
    fi

    return 1
}

# Scope check for URLs (extracts host from URL and checks scope)
is_url_in_scope() {
    local url_raw="$1"
    local target_raw="$2"

    local url
    url="$(printf '%s' "$url_raw" | tr '[:upper:]' '[:lower:]')"

    # Strip scheme (http:// or https://)
    local host_part="${url#http://}"
    host_part="${host_part#https://}"

    # Strip path, query, and fragments
    host_part="${host_part%%/*}"
    host_part="${host_part%%\?*}"
    host_part="${host_part%%\#*}"

    # Strip port if present
    host_part="${host_part%%:*}"

    is_in_scope "$host_part" "$target_raw"
}

# Filter an input file of domains, writing only strictly in-scope domains to output
filter_in_scope() {
    local target_domain="$1"
    local input_file="$2"
    local output_file="$3"

    local norm_target
    norm_target="$(normalize_domain "$target_domain")"

    if [[ ! -f "$input_file" ]]; then
        log_error "filter_in_scope: Input file not found: $input_file"
        return 1
    fi

    local temp_out
    temp_out="$(mktemp "${output_file}.tmp.XXXXXX" 2>/dev/null || printf '%s.tmp' "$output_file")"

    local in_scope_count=0
    local rejected_count=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        local candidate
        candidate="$(normalize_domain "$line")"

        # Skip empty lines or comments
        if [[ -z "$candidate" || "$candidate" == \#* ]]; then
            continue
        fi

        if is_in_scope "$candidate" "$norm_target"; then
            printf '%s\n' "$candidate" >> "$temp_out"
            in_scope_count=$(( in_scope_count + 1 ))
        else
            rejected_count=$(( rejected_count + 1 ))
            log_debug "Rejected out-of-scope domain: $candidate (target: $norm_target)"
        fi
    done < "$input_file"

    # Deduplicate and write to final destination
    if [[ -f "$temp_out" ]]; then
        sort -u "$temp_out" > "$output_file"
        rm -f "$temp_out"
    else
        : > "$output_file"
    fi

    if (( rejected_count > 0 )); then
        log_warn "Scope enforcement filtered out $rejected_count out-of-scope domain(s)."
    fi

    return 0
}

# Filter an input file of URLs, writing only strictly in-scope URLs to output
filter_urls_in_scope() {
    local target_domain="$1"
    local input_file="$2"
    local output_file="$3"

    local norm_target
    norm_target="$(normalize_domain "$target_domain")"

    if [[ ! -f "$input_file" ]]; then
        log_error "filter_urls_in_scope: Input file not found: $input_file"
        return 1
    fi

    local temp_out
    temp_out="$(mktemp "${output_file}.tmp.XXXXXX" 2>/dev/null || printf '%s.tmp' "$output_file")"

    local in_scope_count=0
    local rejected_count=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Trim whitespace
        local url="${line#"${line%%[![:space:]]*}"}"
        url="${url%"${url##*[![:space:]]}"}"

        if [[ -z "$url" || "$url" == \#* ]]; then
            continue
        fi

        if is_url_in_scope "$url" "$norm_target"; then
            printf '%s\n' "$url" >> "$temp_out"
            in_scope_count=$(( in_scope_count + 1 ))
        else
            rejected_count=$(( rejected_count + 1 ))
            log_debug "Rejected out-of-scope URL: $url (target: $norm_target)"
        fi
    done < "$input_file"

    if [[ -f "$temp_out" ]]; then
        sort -u "$temp_out" > "$output_file"
        rm -f "$temp_out"
    else
        : > "$output_file"
    fi

    if (( rejected_count > 0 )); then
        log_warn "Scope enforcement filtered out $rejected_count out-of-scope URL(s)."
    fi

    return 0
}