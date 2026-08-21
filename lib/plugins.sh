#!/usr/bin/env bash

# ============================================
# Recon Framework - Plugin Library
# ============================================

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

    wc -l < "$output_file"
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


# Merge and deduplicate subdomain results
merge_subdomains() {

    local subdomain_dir="$1"
    local domain="$2"
    local output_file="${subdomain_dir}/all.txt"
    local subfinder_file="${subdomain_dir}/subfinder.txt"
    local assetfinder_file="${subdomain_dir}/assetfinder.txt"

    log_info "Merging subdomain results"

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

    {
        printf '%s\n' "$domain"
        cat "$subfinder_file" "$assetfinder_file"
    } |
        sed '/^$/d' |
        sort -u > "$output_file"
    local pipeline_status=("${PIPESTATUS[@]}")

    if [[ "${pipeline_status[0]}" -ne 0 ||
          "${pipeline_status[1]}" -ne 0 ||
          "${pipeline_status[2]}" -ne 0 ]]; then
        log_error "Failed to merge subdomain results."
        return 1
    fi

    local count
    if ! count=$(count_result_lines "$output_file"); then
        log_error "Merged subdomain output could not be read: $output_file"
        return 1
    fi

    log_stage_result "Subdomain merge" "$count" "unique domains"
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

    if ! prepare_output_directory "$output_file"; then
        return 1
    fi

    if [[ ! -s "$input_file" ]]; then
        log_stage_skipped "DNSX" "no subdomains found"
        if ! : > "$output_file"; then
            log_error "Failed to create DNSX output file: $output_file"
            return 1
        fi
        return 0
    fi

    if ! dnsx -l "$input_file" -silent -o "$output_file"; then
        log_error "DNSX failed"
        return 1
    fi

    if ! ensure_result_file "$output_file"; then
        return 1
    fi

    local count
    if ! count=$(count_result_lines "$output_file"); then
        log_error "DNSX output could not be read: $output_file"
        return 1
    fi

    log_stage_result "DNSX" "$count" "resolved hosts"
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

    if ! prepare_output_directory "$output_file"; then
        return 1
    fi

    if [[ ! -s "$input_file" ]]; then
        log_stage_skipped "HTTPX" "no resolved hosts found"
        if ! : > "$output_file"; then
            log_error "Failed to create HTTPX output file: $output_file"
            return 1
        fi
        return 0
    fi

    if ! httpx \
        -l "$input_file" \
        -silent \
        -status-code \
        -title \
        -tech-detect \
        -server \
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


# Extract clean URLs from HTTPX output
extract_live_urls() {

    local input_file="$1"
    local output_file="$2"

    log_info "Extracting live URLs"

    if [[ ! -f "$input_file" ]]; then
        log_error "HTTPX output not found: $input_file"
        return 1
    fi

    if ! prepare_output_directory "$output_file"; then
        return 1
    fi

    sed -E 's/ \[.*$//' "$input_file" |
        sed '/^$/d' |
        sort -u > "$output_file"
    local pipeline_status=("${PIPESTATUS[@]}")

    if [[ "${pipeline_status[0]}" -ne 0 ||
          "${pipeline_status[1]}" -ne 0 ||
          "${pipeline_status[2]}" -ne 0 ]]; then
        log_error "Failed to extract live URLs."
        return 1
    fi

    local count
    if ! count=$(count_result_lines "$output_file"); then
        log_error "Live URL output could not be read: $output_file"
        return 1
    fi

    log_stage_result "Live URL extraction" "$count" "live URLs"
}


# Crawl live URLs using Katana
run_katana() {

    local input_file="$1"
    local output_file="$2"

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

    if [[ ! -s "$input_file" ]]; then
        log_stage_skipped "Katana" "no live URLs found"
        if ! : > "$output_file"; then
            log_error "Failed to create Katana output file: $output_file"
            return 1
        fi
        return 0
    fi

    if ! katana \
        -list "$input_file" \
        -silent \
        -o "$output_file"; then
        log_error "Katana failed"
        return 1
    fi

    if ! ensure_result_file "$output_file"; then
        return 1
    fi

    local count
    if ! count=$(count_result_lines "$output_file"); then
        log_error "Katana output could not be read: $output_file"
        return 1
    fi

    log_stage_result "Katana" "$count" "URLs"
}


# Run Nuclei vulnerability scanning
run_nuclei() {

    local input_file="$1"
    local output_file="$2"

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

    if [[ ! -s "$input_file" ]]; then
        log_stage_skipped "Nuclei" "no live URLs found"
        if ! : > "$output_file"; then
            log_error "Failed to create Nuclei output file: $output_file"
            return 1
        fi
        return 0
    fi

    if ! nuclei \
        -l "$input_file" \
        -silent \
        -jsonl \
        -o "$output_file"; then
        log_error "Nuclei scan failed"
        return 1
    fi

    if ! ensure_result_file "$output_file"; then
        return 1
    fi

    local count
    if ! count=$(count_result_lines "$output_file"); then
        log_error "Nuclei output could not be read: $output_file"
        return 1
    fi

    log_stage_result "Nuclei" "$count" "findings"
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

    if ! prepare_output_directory "$output_file"; then
        return 1
    fi

    if [[ ! -s "$input_file" ]]; then
        log_stage_skipped "Naabu" "no resolved hosts found"
        if ! : > "$output_file"; then
            log_error "Failed to create Naabu output file: $output_file"
            return 1
        fi
        return 0
    fi

    if ! naabu \
        -list "$input_file" \
        -silent \
        -o "$output_file"; then
        log_error "Naabu failed"
        return 1
    fi

    if ! ensure_result_file "$output_file"; then
        return 1
    fi

    local count
    if ! count=$(count_result_lines "$output_file"); then
        log_error "Naabu output could not be read: $output_file"
        return 1
    fi

    log_stage_result "Naabu" "$count" "open ports"
}