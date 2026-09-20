#!/usr/bin/env bash

# ============================================
# Recon Framework - Master Controller
# Author : Akashdeep Singh
# Canonical version tracked in VERSION
# ============================================

set -Eeuo pipefail

# -------------------------------
# Base Directory & Configuration
# -------------------------------

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./config.sh
source "$BASE_DIR/config.sh"

# -------------------------------
# Load Framework Libraries
# -------------------------------

# shellcheck source=./lib/logger.sh
source "$BASE_DIR/lib/logger.sh"
# shellcheck source=./lib/helpers.sh
source "$BASE_DIR/lib/helpers.sh"
# shellcheck source=./lib/filesystem.sh
source "$BASE_DIR/lib/filesystem.sh"
# shellcheck source=./lib/validation.sh
source "$BASE_DIR/lib/validation.sh"
# shellcheck source=./lib/parser.sh
source "$BASE_DIR/lib/parser.sh"
# shellcheck source=./lib/parallel.sh
source "$BASE_DIR/lib/parallel.sh"
# shellcheck source=./lib/progress.sh
source "$BASE_DIR/lib/progress.sh"
# shellcheck source=./lib/report.sh
source "$BASE_DIR/lib/report.sh"
# shellcheck source=./lib/manifest.sh
source "$BASE_DIR/lib/manifest.sh"
# shellcheck source=./lib/plugins.sh
source "$BASE_DIR/lib/plugins.sh"
# shellcheck source=./lib/orchestration.sh
source "$BASE_DIR/lib/orchestration.sh"
# shellcheck source=./lib/cli.sh
source "$BASE_DIR/lib/cli.sh"

# -------------------------------
# Signal & Exit Traps
# -------------------------------

CURRENT_WORKSPACE=""

# shellcheck disable=SC2329
cleanup() {
    local exit_code=$?
    cleanup_parallel_tasks 2>/dev/null || true
    if (( exit_code != 0 )); then
        if [[ -n "${CURRENT_WORKSPACE:-}" && -f "${CURRENT_WORKSPACE}/manifest.json" ]]; then
            finalize_manifest "$CURRENT_WORKSPACE" "failed" 2>/dev/null || true
        fi
        log_error "Framework exited with status $exit_code."
    fi
}

trap cleanup EXIT
trap 'log_error "Reconnaissance interrupted by user signal."; exit 130' INT TERM

# -------------------------------
# Main Orchestrator
# -------------------------------

main() {
    # Parse CLI flags, options, and target domain
    parse_cli_args "$@"

    print_banner
    log_info "Target : $DOMAIN"

    if ! create_workspace "$DOMAIN"; then
        log_error "Framework failed: unable to create workspace for $DOMAIN"
        return 1
    fi

    CURRENT_WORKSPACE="${OUTPUT_DIR}/${DOMAIN}"
    local workspace="$CURRENT_WORKSPACE"
    export LOG_FILE="${workspace}/logs/recon.log"

    # Initialize manifest tracking
    init_manifest "$workspace" "$DOMAIN" \
        "${DNSX_THREADS:-50}" \
        "${HTTPX_RATE_LIMIT:-150}" \
        "${STAGE_TIMEOUT:-300}" \
        "${STAGE_RETRIES:-1}" \
        "${RESUME_MODE:-0}" \
        "${CLI_STAGES:-all}" \
        "${CLI_SKIP:-}"

    # Validate stage dependencies before execution
    if ! validate_pipeline_dependencies "$workspace"; then
        finalize_manifest "$workspace" "failed"
        return 1
    fi

    local subdomain_dir="${workspace}/subdomains"
    local subfinder_output="${subdomain_dir}/subfinder.txt"
    local assetfinder_output="${subdomain_dir}/assetfinder.txt"
    local merged_subdomains="${subdomain_dir}/all.txt"

    local dns_output="${workspace}/dns/resolved.txt"
    local ports_output="${workspace}/ports/naabu.txt"
    local web_candidates="${workspace}/ports/web_candidates.txt"
    local http_targets="${workspace}/live/targets.txt"
    local live_output="${workspace}/live/httpx.txt"
    local clean_urls="${workspace}/live/urls.txt"
    local katana_output="${workspace}/urls/katana.txt"
    local nuclei_output="${workspace}/nuclei/findings.jsonl"

    log_success "Framework Started. Workspace: $workspace"
    log_info "Persistent log: $LOG_FILE"

    local total_stages=7

    # -------------------------------
    # Stage 1: Subdomains
    # -------------------------------
    print_stage_step 1 "$total_stages" "Subdomains (Passive Enumeration & Merge)"

    # shellcheck disable=SC2329
    run_subdomains_stage() {
        if [[ "${PARALLEL_PASSIVE:-true}" == "true" ]]; then
            export -f _log_message run_subfinder run_assetfinder prepare_output_directory ensure_result_file count_result_lines log_stage_result log_info log_success log_warn log_error log_debug command_exists create_directory
            export FRAMEWORK_NAME FRAMEWORK_VERSION RED GREEN YELLOW BLUE CYAN RESET OUTPUT_DIR LOG_FILE VERBOSE

            run_parallel_stages \
                "Subfinder" \
                "run_subfinder '$DOMAIN' '$subfinder_output'" \
                "Assetfinder" \
                "run_assetfinder '$DOMAIN' '$assetfinder_output'"
        else
            run_subfinder "$DOMAIN" "$subfinder_output" && run_assetfinder "$DOMAIN" "$assetfinder_output"
        fi && merge_subdomains "$subdomain_dir" "$DOMAIN"
    }

    if ! run_pipeline_stage "subdomains" "Subdomain Discovery" "$merged_subdomains" run_subdomains_stage; then
        return 1
    fi

    # -------------------------------
    # Stage 2: DNS Resolution
    # -------------------------------
    print_stage_step 2 "$total_stages" "DNS Resolution (DNSX)"

    if ! run_pipeline_stage "dns" "DNS Resolution" "$dns_output" \
        run_dnsx "$DOMAIN" "$merged_subdomains" "$dns_output"; then
        return 1
    fi

    # -------------------------------
    # Stage 3: Port Discovery (Naabu)
    # -------------------------------
    print_stage_step 3 "$total_stages" "Port Discovery (Naabu)"

    if ! run_pipeline_stage "ports" "Port Scanning" "$ports_output" \
        run_naabu "$DOMAIN" "$dns_output" "$ports_output"; then
        return 1
    fi

    # -------------------------------
    # Stage 4: HTTP Probing (HTTPX)
    # -------------------------------
    print_stage_step 4 "$total_stages" "HTTP Probing (HTTPX)"

    # shellcheck disable=SC2329
    run_live_stage() {
        {
            if [[ -s "$dns_output" ]]; then
                awk '{print $1}' "$dns_output"
            fi
            if [[ -s "$web_candidates" ]]; then
                cat "$web_candidates"
            fi
        } | sed '/^$/d' | sort -u > "$http_targets"

        run_httpx "$DOMAIN" "$http_targets" "$live_output" && \
        extract_live_urls "$DOMAIN" "$live_output" "$clean_urls"
    }

    if ! run_pipeline_stage "live" "HTTP Probing" "$clean_urls" run_live_stage; then
        return 1
    fi

    # -------------------------------
    # Stage 5: URL Crawling (Katana)
    # -------------------------------
    print_stage_step 5 "$total_stages" "URL Crawling (Katana)"

    if ! run_pipeline_stage "crawling" "URL Crawling" "$katana_output" \
        run_katana "$DOMAIN" "$clean_urls" "$katana_output"; then
        return 1
    fi

    # -------------------------------
    # Stage 6: Vulnerability Scanning (Nuclei)
    # -------------------------------
    print_stage_step 6 "$total_stages" "Vulnerability Detection (Nuclei)"

    # shellcheck disable=SC2329
    run_vuln_stage() {
        local vuln_input="$katana_output"
        if [[ ! -s "$vuln_input" && -s "$clean_urls" ]]; then
            vuln_input="$clean_urls"
        fi
        run_nuclei "$DOMAIN" "$vuln_input" "$nuclei_output"
    }

    if ! run_pipeline_stage "vuln" "Vulnerability Scanning" "$nuclei_output" run_vuln_stage; then
        return 1
    fi

    # -------------------------------
    # Stage 7: Reporting
    # -------------------------------
    print_stage_step 7 "$total_stages" "Report Generation"

    # shellcheck disable=SC2329
    run_reports_stage() {
        generate_reports "$workspace" "$DOMAIN"
    }

    if ! run_pipeline_stage "reports" "Report Generation" "${workspace}/reports/summary.md" run_reports_stage; then
        return 1
    fi

    # Finalize manifest
    finalize_manifest "$workspace" "success"

    log_success "Reconnaissance completed successfully for $DOMAIN"
    return 0
}

main "$@"
exit $?
