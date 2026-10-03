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
# Phase 5.2: Load new libraries
# -------------------------------
# shellcheck source=./lib/jsonl_logger.sh
source "$BASE_DIR/lib/jsonl_logger.sh"
# shellcheck source=./lib/rate_limit.sh
source "$BASE_DIR/lib/rate_limit.sh"
# shellcheck source=./lib/config_validation.sh
source "$BASE_DIR/lib/config_validation.sh"

# -------------------------------
# Signal & Exit Traps
# -------------------------------

CURRENT_WORKSPACE=""

# shellcheck disable=SC2317,SC2329
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
# Target Pipeline Execution
# -------------------------------

run_target_pipeline() {
    local target_domain="$1"
    DOMAIN="$target_domain"

    CURRENT_WORKSPACE="${OUTPUT_DIR}/${DOMAIN}"
    local workspace="$CURRENT_WORKSPACE"
    export LOG_FILE="${workspace}/logs/recon.log"

    if ! create_workspace "$DOMAIN"; then
        log_error "Framework failed: unable to create workspace for $DOMAIN"
        return 1
    fi

    # Phase 5.2: Initialize JSONL logging
    local jsonl_log_file="${workspace}/logs/recon.jsonl"
    jsonl_init "$(jsonl_generate_run_id)" "$jsonl_log_file"
    jsonl_run_start "$DOMAIN"

    local run_start_epoch
    run_start_epoch="$(date +%s%3N 2>/dev/null || date +%s)"

    log_info "Target : $DOMAIN"

    # Phase 5.2: Initialize rate limiting
    rate_limit_init_from_cli

    # Phase 5.2: Validate configuration before execution
    if ! config_validate_all; then
        jsonl_emit "run_complete" "status" "failed" "error" "config_validation_failed" "timestamp" "$(jsonl_timestamp)"
        return 1
    fi

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
        jsonl_emit "run_complete" "status" "failed" "error" "dependency_validation_failed" "timestamp" "$(jsonl_timestamp)"
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
    jsonl_stage_start "subdomains" "$DOMAIN"

    local stage_start_epoch
    stage_start_epoch="$(date +%s%3N 2>/dev/null || date +%s)"

    if ! run_pipeline_stage "subdomains" "Subdomain Discovery" "$merged_subdomains" \
        execute_subdomains_stage "$DOMAIN" "$subdomain_dir" "$subfinder_output" "$assetfinder_output"; then
        jsonl_stage_complete "subdomains" "failed" "$(($(date +%s%3N 2>/dev/null || date +%s) - stage_start_epoch))" "0"
        jsonl_emit "run_complete" "status" "failed" "error" "stage_failed" "failed_stage" "subdomains" "timestamp" "$(jsonl_timestamp)"
        return 1
    fi

    local subdomain_count
    subdomain_count="$(count_result_lines "$merged_subdomains" 2>/dev/null || echo 0)"
    jsonl_stage_complete "subdomains" "success" "$(($(date +%s%3N 2>/dev/null || date +%s) - stage_start_epoch))" "$subdomain_count"

    # -------------------------------
    # Stage 2: DNS Resolution
    # -------------------------------
    print_stage_step 2 "$total_stages" "DNS Resolution (DNSX)"
    jsonl_stage_start "dns" "$DOMAIN"
    stage_start_epoch="$(date +%s%3N 2>/dev/null || date +%s)"

    if ! run_pipeline_stage "dns" "DNS Resolution" "$dns_output" \
        run_dnsx "$DOMAIN" "$merged_subdomains" "$dns_output"; then
        jsonl_stage_complete "dns" "failed" "$(($(date +%s%3N 2>/dev/null || date +%s) - stage_start_epoch))" "0"
        jsonl_emit "run_complete" "status" "failed" "error" "stage_failed" "failed_stage" "dns" "timestamp" "$(jsonl_timestamp)"
        return 1
    fi

    local dns_count
    dns_count="$(count_result_lines "$dns_output" 2>/dev/null || echo 0)"
    jsonl_stage_complete "dns" "success" "$(($(date +%s%3N 2>/dev/null || date +%s) - stage_start_epoch))" "$dns_count"

    # -------------------------------
    # Stage 3: Port Discovery (Naabu)
    # -------------------------------
    print_stage_step 3 "$total_stages" "Port Discovery (Naabu)"
    jsonl_stage_start "ports" "$DOMAIN"
    stage_start_epoch="$(date +%s%3N 2>/dev/null || date +%s)"

    if ! run_pipeline_stage "ports" "Port Scanning" "$ports_output" \
        run_naabu "$DOMAIN" "$dns_output" "$ports_output"; then
        jsonl_stage_complete "ports" "failed" "$(($(date +%s%3N 2>/dev/null || date +%s) - stage_start_epoch))" "0"
        jsonl_emit "run_complete" "status" "failed" "error" "stage_failed" "failed_stage" "ports" "timestamp" "$(jsonl_timestamp)"
        return 1
    fi

    local ports_count
    ports_count="$(count_result_lines "$ports_output" 2>/dev/null || echo 0)"
    jsonl_stage_complete "ports" "success" "$(($(date +%s%3N 2>/dev/null || date +%s) - stage_start_epoch))" "$ports_count"

    # -------------------------------
    # Stage 4: HTTP Probing (HTTPX)
    # -------------------------------
    print_stage_step 4 "$total_stages" "HTTP Probing (HTTPX)"
    jsonl_stage_start "live" "$DOMAIN"
    stage_start_epoch="$(date +%s%3N 2>/dev/null || date +%s)"

    if ! run_pipeline_stage "live" "HTTP Probing" "$clean_urls" \
        execute_live_stage "$DOMAIN" "$dns_output" "$web_candidates" "$http_targets" "$live_output" "$clean_urls"; then
        jsonl_stage_complete "live" "failed" "$(($(date +%s%3N 2>/dev/null || date +%s) - stage_start_epoch))" "0"
        jsonl_emit "run_complete" "status" "failed" "error" "stage_failed" "failed_stage" "live" "timestamp" "$(jsonl_timestamp)"
        return 1
    fi

    local live_count
    live_count="$(count_result_lines "$clean_urls" 2>/dev/null || echo 0)"
    jsonl_stage_complete "live" "success" "$(($(date +%s%3N 2>/dev/null || date +%s) - stage_start_epoch))" "$live_count"

    # -------------------------------
    # Stage 5: URL Crawling (Katana)
    # -------------------------------
    print_stage_step 5 "$total_stages" "URL Crawling (Katana)"
    jsonl_stage_start "crawling" "$DOMAIN"
    stage_start_epoch="$(date +%s%3N 2>/dev/null || date +%s)"

    if ! run_pipeline_stage "crawling" "URL Crawling" "$katana_output" \
        run_katana "$DOMAIN" "$clean_urls" "$katana_output"; then
        jsonl_stage_complete "crawling" "failed" "$(($(date +%s%3N 2>/dev/null || date +%s) - stage_start_epoch))" "0"
        jsonl_emit "run_complete" "status" "failed" "error" "stage_failed" "failed_stage" "crawling" "timestamp" "$(jsonl_timestamp)"
        return 1
    fi

    local crawl_count
    crawl_count="$(count_result_lines "$katana_output" 2>/dev/null || echo 0)"
    jsonl_stage_complete "crawling" "success" "$(($(date +%s%3N 2>/dev/null || date +%s) - stage_start_epoch))" "$crawl_count"

    # -------------------------------
    # Stage 6: Vulnerability Scanning (Nuclei)
    # -------------------------------
    print_stage_step 6 "$total_stages" "Vulnerability Detection (Nuclei)"
    jsonl_stage_start "vuln" "$DOMAIN"
    stage_start_epoch="$(date +%s%3N 2>/dev/null || date +%s)"

    if ! run_pipeline_stage "vuln" "Vulnerability Scanning" "$nuclei_output" \
        execute_vuln_stage "$DOMAIN" "$katana_output" "$clean_urls" "$nuclei_output"; then
        jsonl_stage_complete "vuln" "failed" "$(($(date +%s%3N 2>/dev/null || date +%s) - stage_start_epoch))" "0"
        jsonl_emit "run_complete" "status" "failed" "error" "stage_failed" "failed_stage" "vuln" "timestamp" "$(jsonl_timestamp)"
        return 1
    fi

    local vuln_count
    vuln_count="$(count_result_lines "$nuclei_output" 2>/dev/null || echo 0)"
    jsonl_stage_complete "vuln" "success" "$(($(date +%s%3N 2>/dev/null || date +%s) - stage_start_epoch))" "$vuln_count"

    # -------------------------------
    # Stage 7: Reporting
    # -------------------------------
    print_stage_step 7 "$total_stages" "Report Generation"
    jsonl_stage_start "reports" "$DOMAIN"
    stage_start_epoch="$(date +%s%3N 2>/dev/null || date +%s)"

    if ! run_pipeline_stage "reports" "Report Generation" "${workspace}/reports/summary.md" \
        execute_reports_stage "$workspace" "$DOMAIN"; then
        jsonl_stage_complete "reports" "failed" "$(($(date +%s%3N 2>/dev/null || date +%s) - stage_start_epoch))" "0"
        jsonl_emit "run_complete" "status" "failed" "error" "stage_failed" "failed_stage" "reports" "timestamp" "$(jsonl_timestamp)"
        return 1
    fi

    jsonl_stage_complete "reports" "success" "$(($(date +%s%3N 2>/dev/null || date +%s) - stage_start_epoch))" "1"

    # Finalize manifest
    finalize_manifest "$workspace" "success"

    local run_end_epoch
    run_end_epoch="$(date +%s%3N 2>/dev/null || date +%s)"
    local run_duration_ms=$(( run_end_epoch - run_start_epoch ))

    log_success "Reconnaissance completed successfully for $DOMAIN"
    jsonl_emit "run_complete" "status" "success" "duration_ms" "$run_duration_ms" "targets_count" "1"

    return 0
}

# -------------------------------
# Main Orchestrator
# -------------------------------

main() {
    # Parse CLI flags, options, and target domain(s)
    parse_cli_args "$@"

    # Handle --self-test (exits without requiring a target)
    if [[ "${SELF_TEST:-0}" -eq 1 ]]; then
        if run_self_test; then
            exit 0
        else
            exit 1
        fi
    fi

    print_banner

    local total_targets=${#TARGET_DOMAINS[@]}
    local target_failures=0
    local target_idx=0

    if (( total_targets > 1 )); then
        log_info "Initiating reconnaissance across $total_targets target(s): ${TARGET_DOMAINS[*]}"
    fi

    for target in "${TARGET_DOMAINS[@]}"; do
        target_idx=$(( target_idx + 1 ))
        if (( total_targets > 1 )); then
            echo ""
            log_info "=========================================================="
            log_info "Target [${target_idx}/${total_targets}]: ${target}"
            log_info "=========================================================="
        fi

        if ! run_target_pipeline "$target"; then
            target_failures=$(( target_failures + 1 ))
            log_error "Pipeline failed for target: $target"
        fi
    done

    if (( total_targets > 1 )); then
        generate_multi_target_summary "${OUTPUT_DIR}" "${TARGET_DOMAINS[@]}"
    fi

    if (( target_failures > 0 )); then
        log_error "Reconnaissance completed with $target_failures failure(s) across $total_targets target(s)."
        return 1
    fi

    if (( total_targets > 1 )); then
        log_success "All $total_targets target assessments completed successfully."
    fi
    return 0
}

main "$@"
exit $?
