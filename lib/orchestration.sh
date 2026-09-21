#!/usr/bin/env bash

# ============================================
# Recon Framework - Pipeline Orchestration
# ============================================

ORCH_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v log_error >/dev/null 2>&1; then
    # shellcheck source=./logger.sh
    source "$ORCH_LIB_DIR/logger.sh"
fi
if ! command -v run_with_timeout >/dev/null 2>&1; then
    # shellcheck source=./parallel.sh
    source "$ORCH_LIB_DIR/parallel.sh"
fi
if ! command -v update_stage_manifest >/dev/null 2>&1; then
    # shellcheck source=./manifest.sh
    source "$ORCH_LIB_DIR/manifest.sh"
fi
if ! command -v count_result_lines >/dev/null 2>&1; then
    # shellcheck source=./plugins.sh
    source "$ORCH_LIB_DIR/plugins.sh"
fi

# Canonical stages and aliases mapping
normalize_stage_name() {
    local raw
    raw="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    case "$raw" in
        subdomain|subdomains) echo "subdomains" ;;
        dns|dnsx) echo "dns" ;;
        port|ports|naabu) echo "ports" ;;
        live|httpx|http) echo "live" ;;
        crawling|crawl|crawler|katana|urls) echo "crawling" ;;
        vuln|vulns|nuclei) echo "vuln" ;;
        report|reports) echo "reports" ;;
        *) echo "$raw" ;;
    esac
}

# Determine if a stage is selected for execution
is_stage_selected() {
    local query
    query="$(normalize_stage_name "$1")"

    # 1. Check if explicitly in CLI_SKIP
    if [[ -n "${CLI_SKIP:-}" ]]; then
        local IFS=','
        local skip_item
        read -r -a skip_array <<< "$CLI_SKIP"
        for skip_item in "${skip_array[@]}"; do
            skip_item="${skip_item// /}"
            if [[ "$(normalize_stage_name "$skip_item")" == "$query" ]]; then
                return 1
            fi
        done
    fi

    # 2. Check if all stages are enabled
    if [[ "${CLI_STAGES:-all}" == "all" ]]; then
        return 0
    fi

    # 3. Check if in CLI_STAGES list
    local IFS=','
    local stage_item
    read -r -a stage_array <<< "$CLI_STAGES"
    for stage_item in "${stage_array[@]}"; do
        stage_item="${stage_item// /}"
        if [[ "$(normalize_stage_name "$stage_item")" == "$query" ]]; then
            return 0
        fi
    done

    return 1
}

# Validate that selected stages have required upstream dependencies or existing outputs
validate_pipeline_dependencies() {
    local workspace="$1"

    if is_stage_selected "dns"; then
        if ! is_stage_selected "subdomains" && [[ ! -s "${workspace}/subdomains/all.txt" ]]; then
            log_error "Dependency failure: Stage 'dns' requires 'subdomains' or existing '${workspace}/subdomains/all.txt'."
            return 1
        fi
    fi

    if is_stage_selected "ports"; then
        if ! is_stage_selected "dns" && [[ ! -s "${workspace}/dns/resolved.txt" ]]; then
            log_error "Dependency failure: Stage 'ports' requires 'dns' or existing '${workspace}/dns/resolved.txt'."
            return 1
        fi
    fi

    if is_stage_selected "live"; then
        if ! is_stage_selected "dns" && [[ ! -s "${workspace}/dns/resolved.txt" ]]; then
            log_error "Dependency failure: Stage 'live' requires 'dns' or existing '${workspace}/dns/resolved.txt'."
            return 1
        fi
    fi

    if is_stage_selected "crawling"; then
        if ! is_stage_selected "live" && [[ ! -s "${workspace}/live/urls.txt" ]]; then
            log_error "Dependency failure: Stage 'crawling' requires 'live' or existing '${workspace}/live/urls.txt'."
            return 1
        fi
    fi

    if is_stage_selected "vuln"; then
        if ! is_stage_selected "crawling" && ! is_stage_selected "live" && [[ ! -s "${workspace}/urls/katana.txt" && ! -s "${workspace}/live/urls.txt" ]]; then
            log_error "Dependency failure: Stage 'vuln' requires 'crawling' or 'live' or existing URL inputs."
            return 1
        fi
    fi

    return 0
}

# Validate that stage output artifact is valid and complete for resumption
is_stage_output_valid() {
    local stage_key="$1"
    local check_file="$2"
    local workspace="$3"

    case "$stage_key" in
        subdomains)
            [[ -f "$check_file" && -s "$check_file" ]]
            ;;
        dns)
            [[ -f "$check_file" && -s "$check_file" ]]
            ;;
        ports)
            [[ -f "$check_file" && -s "$check_file" && -f "${workspace}/ports/ports.jsonl" ]]
            ;;
        live)
            [[ -f "$check_file" && -s "$check_file" && -f "${workspace}/live/httpx.txt" ]]
            ;;
        crawling)
            [[ -f "$check_file" && -s "$check_file" ]]
            ;;
        vuln)
            [[ -f "$check_file" && -s "${workspace}/nuclei/summary.json" ]]
            ;;
        reports)
            [[ -f "$check_file" && -s "$check_file" ]]
            ;;
        *)
            [[ -f "$check_file" && -s "$check_file" ]]
            ;;
    esac
}

# Execute a pipeline stage with retry supervision, timeout, and manifest status tracking
run_pipeline_stage() {
    local stage_key="$1"
    local stage_label="$2"
    local check_file="$3"
    shift 3

    # Check stage selection
    if ! is_stage_selected "$stage_key"; then
        log_info "Skipping [${stage_label}] (excluded by stage selection or skip flag)."
        update_stage_manifest "$CURRENT_WORKSPACE" "$stage_key" "skipped" 0 0 0
        return 0
    fi

    # Check resumption
    if [[ "${RESUME_MODE:-0}" -eq 1 ]] && is_stage_output_valid "$stage_key" "$check_file" "$CURRENT_WORKSPACE"; then
        log_info "Skipping [${stage_label}] (resumed: output exists and is verified valid)."
        local resumed_count=0
        if [[ -f "$check_file" ]]; then
            resumed_count="$(count_result_lines "$check_file" 2>/dev/null || echo 0)"
        fi
        update_stage_manifest "$CURRENT_WORKSPACE" "$stage_key" "resumed" 0 "$resumed_count" 0
        return 0
    fi

    # Update manifest to running
    update_stage_manifest "$CURRENT_WORKSPACE" "$stage_key" "running" 0 0 1

    local attempt=1
    local max_attempts=$(( STAGE_RETRIES + 1 ))
    local start_epoch
    start_epoch="$(date +%s)"
    local stage_status=0

    while (( attempt <= max_attempts )); do
        if (( attempt > 1 )); then
            log_warn "Retrying ${stage_label} (attempt ${attempt}/${max_attempts})..."
            update_stage_manifest "$CURRENT_WORKSPACE" "$stage_key" "running" 0 0 "$attempt"
        fi

        stage_status=0
        if [[ "${STAGE_TIMEOUT:-0}" -gt 0 ]]; then
            run_with_timeout "$STAGE_TIMEOUT" "$@" || stage_status=$?
        else
            "$@" || stage_status=$?
        fi

        if [[ "$stage_status" -eq 0 ]]; then
            local end_epoch
            end_epoch="$(date +%s)"
            local duration=$(( end_epoch - start_epoch ))
            local output_count=0
            if [[ -f "$check_file" ]]; then
                output_count="$(count_result_lines "$check_file" 2>/dev/null || echo 0)"
            fi
            update_stage_manifest "$CURRENT_WORKSPACE" "$stage_key" "success" "$duration" "$output_count" "$attempt"
            return 0
        fi

        attempt=$(( attempt + 1 ))
    done

    local end_epoch
    end_epoch="$(date +%s)"
    local duration=$(( end_epoch - start_epoch ))
    update_stage_manifest "$CURRENT_WORKSPACE" "$stage_key" "failed" "$duration" 0 "$max_attempts"
    log_error "$stage_label failed after $max_attempts attempt(s) with status $stage_status. Reconnaissance aborted."
    return "$stage_status"
}

# Execute subdomains stage (passive enumeration & merge)
execute_subdomains_stage() {
    local domain="$1"
    local subdomain_dir="$2"
    local subfinder_output="$3"
    local assetfinder_output="$4"

    if [[ "${PARALLEL_PASSIVE:-true}" == "true" ]]; then
        export -f _log_message run_subfinder run_assetfinder prepare_output_directory ensure_result_file count_result_lines log_stage_result log_info log_success log_warn log_error log_debug command_exists create_directory
        export FRAMEWORK_NAME FRAMEWORK_VERSION RED GREEN YELLOW BLUE CYAN RESET OUTPUT_DIR LOG_FILE VERBOSE

        run_parallel_stages \
            "Subfinder" \
            "run_subfinder '$domain' '$subfinder_output'" \
            "Assetfinder" \
            "run_assetfinder '$domain' '$assetfinder_output'"
    else
        run_subfinder "$domain" "$subfinder_output" && run_assetfinder "$domain" "$assetfinder_output"
    fi && merge_subdomains "$subdomain_dir" "$domain"
}

# Execute live HTTP stage (aggregate DNS and Naabu web ports, probe with HTTPX)
execute_live_stage() {
    local domain="$1"
    local dns_output="$2"
    local web_candidates="$3"
    local http_targets="$4"
    local live_output="$5"
    local clean_urls="$6"

    {
        if [[ -s "$dns_output" ]]; then
            awk '{print $1}' "$dns_output"
        fi
        if [[ -s "$web_candidates" ]]; then
            cat "$web_candidates"
        fi
    } | sed '/^$/d' | sort -u > "$http_targets"

    run_httpx "$domain" "$http_targets" "$live_output" && \
    extract_live_urls "$domain" "$live_output" "$clean_urls"
}

# Execute vulnerability scanning stage (Nuclei on crawled or live URLs)
execute_vuln_stage() {
    local domain="$1"
    local katana_output="$2"
    local clean_urls="$3"
    local nuclei_output="$4"

    local vuln_input="$katana_output"
    if [[ ! -s "$vuln_input" && -s "$clean_urls" ]]; then
        vuln_input="$clean_urls"
    fi
    run_nuclei "$domain" "$vuln_input" "$nuclei_output"
}

# Execute reports generation stage
execute_reports_stage() {
    local workspace="$1"
    local domain="$2"

    generate_reports "$workspace" "$domain"
}
