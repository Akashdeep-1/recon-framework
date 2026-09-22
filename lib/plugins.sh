#!/usr/bin/env bash

# ============================================
# Recon Framework - Plugin Library
# ============================================

PLUGINS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v log_error >/dev/null 2>&1; then
    # shellcheck source=./logger.sh
    source "$PLUGINS_LIB_DIR/logger.sh"
fi
if ! command -v normalize_domain >/dev/null 2>&1; then
    # shellcheck source=./validation.sh
    source "$PLUGINS_LIB_DIR/validation.sh"
fi
if ! command -v parse_hosts_jsonl >/dev/null 2>&1; then
    # shellcheck source=./parser.sh
    source "$PLUGINS_LIB_DIR/parser.sh"
fi

# Create the parent directory for a stage output file.
prepare_output_directory() {
    local output_file="$1"
    local output_dir

    output_dir=$(dirname -- "$output_file") || {
        log_error "Could not determine output directory for: $output_file"
        return 1
    }

    if ! create_directory "$output_dir"; then
        log_error "Failed to create output directory: $output_dir"
        return 1
    fi

    return 0
}

# Ensure a successful stage has a readable output file, including zero results.
ensure_result_file() {
    local output_file="$1"

    if [[ -e "$output_file" && ! -f "$output_file" ]]; then
        log_error "Stage output is not a regular file: $output_file"
        return 1
    fi

    if [[ ! -e "$output_file" ]] && ! : > "$output_file"; then
        log_error "Failed to create stage output file: $output_file"
        return 1
    fi

    return 0
}

# Count output lines and fail when a stage does not provide a readable file.
count_result_lines() {
    local output_file="$1"

    if [[ ! -f "$output_file" ]]; then
        return 1
    fi

    wc -l < "$output_file" | tr -d ' '
}

# Report a successful stage while preserving the distinction between data and no data.
log_stage_result() {
    local stage_name="$1"
    local count="$2"
    local result_label="$3"

    if [[ ! "$count" =~ ^[0-9]+$ ]]; then
        log_error "$stage_name produced an invalid result count."
        return 1
    fi

    if [[ "$count" -eq 0 ]]; then
        log_warn "$stage_name completed successfully: 0 $result_label found (EMPTY RESULT)"
    else
        log_success "$stage_name completed: $count $result_label found"
    fi

    return 0
}

# Report a non-failing stage that cannot run because upstream input is empty.
log_stage_skipped() {
    local stage_name="$1"
    local reason="$2"

    log_warn "$stage_name skipped: $reason (SKIPPED)"
}

# Run Subfinder for passive subdomain enumeration
run_subfinder() {
    local domain="$1"
    local output_file="$2"

    log_info "Running Subfinder on $domain"

    if ! command_exists subfinder; then
        log_error "Subfinder is not installed."
        return 1
    fi

    if ! prepare_output_directory "$output_file"; then
        return 1
    fi

    if ! subfinder -d "$domain" -silent -o "$output_file"; then
        log_error "Subfinder failed for $domain"
        return 1
    fi

    if ! ensure_result_file "$output_file"; then
        return 1
    fi

    local count
    if ! count=$(count_result_lines "$output_file"); then
        log_error "Subfinder output could not be read: $output_file"
        return 1
    fi

    log_stage_result "Subfinder" "$count" "subdomains"
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

    if ! prepare_output_directory "$output_file"; then
        return 1
    fi

    assetfinder --subs-only "$domain" | sort -u > "$output_file"
    local pipeline_status=("${PIPESTATUS[@]}")

    if [[ "${pipeline_status[0]}" -ne 0 || "${pipeline_status[1]}" -ne 0 ]]; then
        log_error "Assetfinder failed for $domain"
        return 1
    fi

    if ! ensure_result_file "$output_file"; then
        return 1
    fi

    local count
    if ! count=$(count_result_lines "$output_file"); then
        log_error "Assetfinder output could not be read: $output_file"
        return 1
    fi

    log_stage_result "Assetfinder" "$count" "subdomains"
}

# Merge, scope-filter, and deduplicate subdomain results
merge_subdomains() {
    local subdomain_dir="$1"
    local domain="$2"
    local output_file="${subdomain_dir}/all.txt"
    local subfinder_file="${subdomain_dir}/subfinder.txt"
    local assetfinder_file="${subdomain_dir}/assetfinder.txt"

    log_info "Merging and scope-filtering subdomain results"

    if [[ -z "$domain" ]]; then
        log_error "Target domain is required to merge subdomains."
        return 1
    fi

    if ! create_directory "$subdomain_dir"; then
        log_error "Failed to create subdomain directory: $subdomain_dir"
        return 1
    fi

    if [[ ! -f "$subfinder_file" || ! -f "$assetfinder_file" ]]; then
        log_error "Subdomain output files are missing."
        return 1
    fi

    local temp_raw
    temp_raw="$(mktemp "${subdomain_dir}/raw.XXXXXX" 2>/dev/null || printf '%s/raw.tmp' "$subdomain_dir")"

    {
        printf '%s\n' "$domain"
        cat "$subfinder_file" "$assetfinder_file"
    } > "$temp_raw"

    # Enforce strict scope: only $domain and valid subdomains (*.$domain)
    if ! filter_in_scope "$domain" "$temp_raw" "$output_file"; then
        rm -f "$temp_raw" 2>/dev/null || true
        log_error "Failed to enforce scope on subdomain results."
        return 1
    fi
    rm -f "$temp_raw" 2>/dev/null || true

    # Emit normalized JSONL model
    parse_hosts_jsonl "$output_file" "${subdomain_dir}/hosts.jsonl" "$domain" "subdomain_merge"

    local count
    if ! count=$(count_result_lines "$output_file"); then
        log_error "Merged subdomain output could not be read: $output_file"
        return 1
    fi

    log_stage_result "Subdomain merge" "$count" "in-scope unique domains"
}

# Resolve discovered subdomains using DNSX
run_dnsx() {
    local domain="$1"
    local input_file="$2"
    local output_file="$3"

    log_info "Running DNSX"

    if ! command_exists dnsx; then
        log_error "DNSX is not installed."
        return 1
    fi

    if [[ ! -f "$input_file" ]]; then
        log_error "Subdomain input file not found: $input_file"
        return 1
    fi

    if ! prepare_output_directory "$output_file"; then
        return 1
    fi

    # Enforce scope check on input file before active resolution
    local scoped_input
    scoped_input="$(mktemp "${input_file}.scoped.XXXXXX" 2>/dev/null || printf '%s.scoped' "$input_file")"
    filter_in_scope "$domain" "$input_file" "$scoped_input"

    if [[ ! -s "$scoped_input" ]]; then
        rm -f "$scoped_input" 2>/dev/null || true
        log_stage_skipped "DNSX" "no in-scope subdomains found"
        if ! : > "$output_file"; then
            log_error "Failed to create DNSX output file: $output_file"
            return 1
        fi
        return 0
    fi

    local threads="${DNSX_THREADS:-50}"
    if ! dnsx -l "$scoped_input" -silent -t "$threads" -o "$output_file"; then
        rm -f "$scoped_input" 2>/dev/null || true
        log_error "DNSX failed"
        return 1
    fi
    rm -f "$scoped_input" 2>/dev/null || true

    if ! ensure_result_file "$output_file"; then
        return 1
    fi

    # Post-resolution scope safety check: extract host token and verify
    local temp_resolved
    temp_resolved="$(mktemp "${output_file}.tmp.XXXXXX" 2>/dev/null || printf '%s.tmp' "$output_file")"
    while IFS= read -r line || [[ -n "$line" ]]; do
        local host_part="${line%%[[:space:]]*}"
        host_part="$(normalize_domain "$host_part")"
        if is_in_scope "$host_part" "$domain"; then
            printf '%s\n' "$line" >> "$temp_resolved"
        fi
    done < "$output_file"
    mv -f "$temp_resolved" "$output_file"

    # Emit normalized JSONL
    local output_dir
    output_dir="$(dirname -- "$output_file")"
    parse_dnsx_output "$output_file" "${output_dir}/resolved.jsonl" "$domain"

    local count
    if ! count=$(count_result_lines "$output_file"); then
        log_error "DNSX output could not be read: $output_file"
        return 1
    fi

    log_stage_result "DNSX" "$count" "resolved hosts"
}

# Discover open ports using Naabu
run_naabu() {
    local domain="$1"
    local input_file="$2"
    local output_file="$3"

    log_info "Running Naabu"

    if ! command_exists naabu; then
        log_error "Naabu is not installed."
        return 1
    fi

    if [[ ! -f "$input_file" ]]; then
        log_error "DNS input file not found: $input_file"
        return 1
    fi

    if ! prepare_output_directory "$output_file"; then
        return 1
    fi

    # Scope validation before scanning
    local temp_hosts scoped_input
    temp_hosts="$(mktemp "${input_file}.hosts.XXXXXX" 2>/dev/null || printf '%s.hosts' "$input_file")"
    awk '{print $1}' "$input_file" | sed '/^$/d' > "$temp_hosts"
    scoped_input="$(mktemp "${input_file}.scoped.XXXXXX" 2>/dev/null || printf '%s.scoped' "$input_file")"
    filter_in_scope "$domain" "$temp_hosts" "$scoped_input"
    rm -f "$temp_hosts" 2>/dev/null || true

    if [[ ! -s "$scoped_input" ]]; then
        rm -f "$scoped_input" 2>/dev/null || true
        log_stage_skipped "Naabu" "no resolved hosts found"
        if ! : > "$output_file"; then
            log_error "Failed to create Naabu output file: $output_file"
            return 1
        fi
        return 0
    fi

    local rate="${NAABU_RATE:-1000}"
    local ports_flag
    if ! ports_flag="$(normalize_naabu_ports "${NAABU_PORTS:-100}")"; then
        log_error "Invalid NAABU_PORTS value: '${NAABU_PORTS:-100}' (expected a positive integer or 'top-N')"
        rm -f "$scoped_input" 2>/dev/null || true
        return 1
    fi

    if ! naabu \
        -list "$scoped_input" \
        -silent \
        -rate "$rate" \
        -top-ports "$ports_flag" \
        -o "$output_file"; then
        rm -f "$scoped_input" 2>/dev/null || true
        log_error "Naabu failed"
        return 1
    fi
    rm -f "$scoped_input" 2>/dev/null || true

    if ! ensure_result_file "$output_file"; then
        return 1
    fi

    local output_dir
    output_dir="$(dirname -- "$output_file")"

    # Emit normalized ports JSONL
    parse_naabu_output "$output_file" "${output_dir}/ports.jsonl" "$domain"

    # Extract non-standard and standard web ports for HTTPX
    extract_web_ports_from_naabu \
        "$output_file" \
        "${output_dir}/web_candidates.txt" \
        "$domain" \
        "${WEB_PORTS:-80,443,8000,8080,8443,8888,9000,9443,3000,5000}"

    local count
    if ! count=$(count_result_lines "$output_file"); then
        log_error "Naabu output could not be read: $output_file"
        return 1
    fi

    log_stage_result "Naabu" "$count" "open ports"
}

# Probe live HTTP/HTTPS services using HTTPX
run_httpx() {
    local domain="$1"
    local input_file="$2"
    local output_file="$3"

    log_info "Running HTTPX"

    if ! command_exists httpx; then
        log_error "HTTPX is not installed."
        return 1
    fi

    if [[ ! -f "$input_file" ]]; then
        log_error "HTTPX target input file not found: $input_file"
        return 1
    fi

    if ! prepare_output_directory "$output_file"; then
        return 1
    fi

    if [[ ! -s "$input_file" ]]; then
        log_stage_skipped "HTTPX" "no target endpoints found"
        if ! : > "$output_file"; then
            log_error "Failed to create HTTPX output file: $output_file"
            return 1
        fi
        return 0
    fi

    local threads="${HTTPX_THREADS:-50}"
    local timeout="${HTTPX_TIMEOUT:-10}"
    local rate_limit="${HTTPX_RATE_LIMIT:-150}"

    if ! httpx \
        -l "$input_file" \
        -silent \
        -status-code \
        -title \
        -tech-detect \
        -server \
        -threads "$threads" \
        -timeout "$timeout" \
        -rate-limit "$rate_limit" \
        -o "$output_file"; then
        log_error "HTTPX failed"
        return 1
    fi

    if ! ensure_result_file "$output_file"; then
        return 1
    fi

    local count
    if ! count=$(count_result_lines "$output_file"); then
        log_error "HTTPX output could not be read: $output_file"
        return 1
    fi

    log_stage_result "HTTPX" "$count" "live HTTP services"
}

# Extract clean in-scope URLs from HTTPX output
extract_live_urls() {
    local domain="$1"
    local input_file="$2"
    local output_file="$3"

    log_info "Extracting and scope-filtering live URLs"

    if [[ ! -f "$input_file" ]]; then
        log_error "HTTPX output not found: $input_file"
        return 1
    fi

    if ! prepare_output_directory "$output_file"; then
        return 1
    fi

    local temp_raw
    temp_raw="$(mktemp "${output_file}.raw.XXXXXX" 2>/dev/null || printf '%s.raw' "$output_file")"

    # Extract the first column (the URL)
    awk '{print $1}' "$input_file" | sed '/^$/d' | sort -u > "$temp_raw"

    # Scope-filter extracted URLs
    filter_urls_in_scope "$domain" "$temp_raw" "$output_file"
    rm -f "$temp_raw" 2>/dev/null || true

    local count
    if ! count=$(count_result_lines "$output_file"); then
        log_error "Live URL output could not be read: $output_file"
        return 1
    fi

    log_stage_result "Live URL extraction" "$count" "live in-scope URLs"
}

# Crawl live URLs using Katana
run_katana() {
    local domain="$1"
    local input_file="$2"
    local output_file="$3"

    log_info "Running Katana"

    if ! command_exists katana; then
        log_error "Katana is not installed or not in PATH."
        return 1
    fi

    if [[ ! -f "$input_file" ]]; then
        log_error "Live URL input file not found: $input_file"
        return 1
    fi

    if ! prepare_output_directory "$output_file"; then
        return 1
    fi

    # Scope validation before crawling
    local scoped_input
    scoped_input="$(mktemp "${input_file}.scoped.XXXXXX" 2>/dev/null || printf '%s.scoped' "$input_file")"
    filter_urls_in_scope "$domain" "$input_file" "$scoped_input"

    if [[ ! -s "$scoped_input" ]]; then
        rm -f "$scoped_input" 2>/dev/null || true
        log_stage_skipped "Katana" "no live in-scope URLs found"
        if ! : > "$output_file"; then
            log_error "Failed to create Katana output file: $output_file"
            return 1
        fi
        return 0
    fi

    local concurrency="${KATANA_CONCURRENCY:-10}"
    local depth="${KATANA_DEPTH:-2}"
    local timeout="${KATANA_TIMEOUT:-10}"

    local raw_output
    raw_output="$(mktemp "${output_file}.raw.XXXXXX" 2>/dev/null || printf '%s.raw' "$output_file")"

    if ! katana \
        -list "$scoped_input" \
        -silent \
        -c "$concurrency" \
        -d "$depth" \
        -ct "$timeout" \
        -o "$raw_output"; then
        rm -f "$scoped_input" "$raw_output" 2>/dev/null || true
        log_error "Katana failed"
        return 1
    fi
    rm -f "$scoped_input" 2>/dev/null || true

    # Ensure crawled URLs stay in scope
    filter_urls_in_scope "$domain" "$raw_output" "$output_file"
    rm -f "$raw_output" 2>/dev/null || true

    if ! ensure_result_file "$output_file"; then
        return 1
    fi

    local output_dir
    output_dir="$(dirname -- "$output_file")"
    parse_katana_output "$output_file" "${output_dir}/urls.jsonl" "$domain"

    local count
    if ! count=$(count_result_lines "$output_file"); then
        log_error "Katana output could not be read: $output_file"
        return 1
    fi

    log_stage_result "Katana" "$count" "URLs"
}

# Run Nuclei vulnerability scanning
run_nuclei() {
    local domain="$1"
    local input_file="$2"
    local output_file="$3"

    log_info "Running Nuclei"

    if ! command_exists nuclei; then
        log_error "Nuclei is not installed."
        return 1
    fi

    if [[ ! -f "$input_file" ]]; then
        log_error "URL input file not found: $input_file"
        return 1
    fi

    if ! prepare_output_directory "$output_file"; then
        return 1
    fi

    # Scope validation before vulnerability scanning
    local scoped_input
    scoped_input="$(mktemp "${input_file}.scoped.XXXXXX" 2>/dev/null || printf '%s.scoped' "$input_file")"
    filter_urls_in_scope "$domain" "$input_file" "$scoped_input"

    if [[ ! -s "$scoped_input" ]]; then
        rm -f "$scoped_input" 2>/dev/null || true
        log_stage_skipped "Nuclei" "no live URLs found"
        if ! : > "$output_file"; then
            log_error "Failed to create Nuclei output file: $output_file"
            return 1
        fi
        return 0
    fi

    local concurrency="${NUCLEI_CONCURRENCY:-25}"
    local rate_limit="${NUCLEI_RATE_LIMIT:-150}"
    local timeout="${NUCLEI_TIMEOUT:-10}"
    local severity="${NUCLEI_SEVERITY:-info,low,medium,high,critical}"
    local tags="${NUCLEI_TAGS:-cve,misconfig,exposure,vulnerability}"

    if ! nuclei \
        -l "$scoped_input" \
        -silent \
        -jsonl \
        -c "$concurrency" \
        -rate-limit "$rate_limit" \
        -timeout "$timeout" \
        -severity "$severity" \
        -tags "$tags" \
        -o "$output_file"; then
        rm -f "$scoped_input" 2>/dev/null || true
        log_error "Nuclei scan failed"
        return 1
    fi
    rm -f "$scoped_input" 2>/dev/null || true

    if ! ensure_result_file "$output_file"; then
        return 1
    fi

    local output_dir
    output_dir="$(dirname -- "$output_file")"
    parse_nuclei_findings "$output_file" "${output_dir}/summary.json" "$domain"

    local count
    if ! count=$(count_result_lines "$output_file"); then
        log_error "Nuclei output could not be read: $output_file"
        return 1
    fi

    log_stage_result "Nuclei" "$count" "findings"
}