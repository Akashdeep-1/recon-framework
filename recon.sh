#!/usr/bin/env bash

# ============================================
# Recon Framework
# Author : Akashdeep Singh
# Version: 1.2.0
# ============================================

set -Eeuo pipefail

# -------------------------------
# Base Directory
# -------------------------------

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -------------------------------
# Load Configuration
# -------------------------------

# shellcheck source=./config.sh
source "$BASE_DIR/config.sh"

# -------------------------------
# Load Libraries
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
# shellcheck source=./lib/plugins.sh
source "$BASE_DIR/lib/plugins.sh"

# -------------------------------
# Signal & Exit Traps
# -------------------------------

# shellcheck disable=SC2329
cleanup() {
    local exit_code=$?
    cleanup_parallel_tasks 2>/dev/null || true
    if (( exit_code != 0 )); then
        log_error "Framework exited with status $exit_code."
    fi
}

trap cleanup EXIT
trap 'log_error "Reconnaissance interrupted by user signal."; exit 130' INT TERM

# -------------------------------
# Banner
# -------------------------------

print_banner() {

    echo -e "${CYAN}"

    cat << EOF

██████╗ ███████╗ ██████╗ ██████╗ ███╗   ██╗
██╔══██╗██╔════╝██╔════╝██╔═══██╗████╗  ██║
██████╔╝█████╗  ██║     ██║   ██║██╔██╗ ██║
██╔══██╗██╔══╝  ██║     ██║   ██║██║╚██╗██║
██║  ██║███████╗╚██████╗╚██████╔╝██║ ╚████║
╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝

        ${FRAMEWORK_NAME} v${FRAMEWORK_VERSION}

EOF

    echo -e "${RESET}"
}

# -------------------------------
# Usage
# -------------------------------

usage() {

    cat << EOF

Usage:
  ./recon.sh -d <domain.com> [options]

Options:
  -d <domain>     Target Domain (required)
  -r              Resume mode (skip stages with existing non-empty output)
  -h              Help and usage information

Security Notice:
  This tool is intended strictly for authorized security assessments,
  penetration testing, and bug bounty programs where explicit written
  authorization has been granted. The operator assumes full responsibility
  for ensuring all scans remain strictly in-scope.

Example:
  ./recon.sh -d example.com
  ./recon.sh -d example.com -r

EOF

}

# -------------------------------
# Parse Arguments
# -------------------------------

DOMAIN=""
RESUME_MODE=0

while getopts ":d:rh" opt; do

    case "$opt" in

        d)
            DOMAIN="$OPTARG"
            ;;

        r)
            RESUME_MODE=1
            ;;

        h)
            usage
            exit 0
            ;;

        *)
            usage
            exit 1
            ;;

    esac

done

# -------------------------------
# Validate Target
# -------------------------------

if [[ -z "$DOMAIN" ]]; then
    print_banner
    log_error "No target domain supplied."
    usage
    exit 1
fi

DOMAIN="$(normalize_domain "$DOMAIN")"

if ! validate_domain "$DOMAIN"; then
    exit 1
fi

# -------------------------------
# Stage Helper with Resumption Support
# -------------------------------

run_required_stage() {
    local stage_name="$1"
    local check_file="$2"
    shift 2

    if [[ "$RESUME_MODE" -eq 1 && -f "$check_file" && -s "$check_file" ]]; then
        log_info "Skipping [${stage_name}] (resumed: output exists and is non-empty)."
        return 0
    fi

    local stage_status=0
    "$@" || stage_status=$?

    if [[ "$stage_status" -eq 0 ]]; then
        return 0
    fi

    log_error "$stage_name failed with status $stage_status. Reconnaissance aborted."
    return "$stage_status"
}

# -------------------------------
# Main Orchestrator
# -------------------------------

main() {

    print_banner

    log_info "Target : $DOMAIN"

    if ! create_workspace "$DOMAIN"; then
        log_error "Framework failed: unable to create workspace for $DOMAIN"
        return 1
    fi

    local workspace="${OUTPUT_DIR}/${DOMAIN}"
    export LOG_FILE="${workspace}/logs/recon.log"

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

    local total_stages=8

    # -------------------------------
    # Stage 1: Passive Subdomain Enumeration
    # -------------------------------
    print_stage_step 1 "$total_stages" "Passive Subdomain Enumeration"

    if [[ "${PARALLEL_PASSIVE:-true}" == "true" ]]; then
        local p_needed=0
        if [[ "$RESUME_MODE" -ne 1 || ! -s "$subfinder_output" || ! -s "$assetfinder_output" ]]; then
            p_needed=1
        fi

        if (( p_needed == 1 )); then
            # Export functions and variables for subshell execution
            export -f _log_message run_subfinder run_assetfinder prepare_output_directory ensure_result_file count_result_lines log_stage_result log_info log_success log_warn log_error log_debug command_exists create_directory
            export FRAMEWORK_NAME FRAMEWORK_VERSION RED GREEN YELLOW BLUE CYAN RESET OUTPUT_DIR LOG_FILE

            if ! run_parallel_stages \
                "Subfinder" \
                "run_subfinder '$DOMAIN' '$subfinder_output'" \
                "Assetfinder" \
                "run_assetfinder '$DOMAIN' '$assetfinder_output'"; then
                return 1
            fi
        else
            log_info "Skipping Subfinder and Assetfinder (resumed)."
        fi
    else
        if ! run_required_stage \
            "Subfinder" \
            "$subfinder_output" \
            run_subfinder "$DOMAIN" "$subfinder_output"; then
            return 1
        fi

        if ! run_required_stage \
            "Assetfinder" \
            "$assetfinder_output" \
            run_assetfinder "$DOMAIN" "$assetfinder_output"; then
            return 1
        fi
    fi

    # -------------------------------
    # Stage 2: Subdomain Merge & Scope Enforcement
    # -------------------------------
    print_stage_step 2 "$total_stages" "Subdomain Merge & Scope Enforcement"

    if ! run_required_stage \
        "Subdomain merge" \
        "$merged_subdomains" \
        merge_subdomains "$subdomain_dir" "$DOMAIN"; then
        return 1
    fi

    # -------------------------------
    # Stage 3: DNS Resolution
    # -------------------------------
    print_stage_step 3 "$total_stages" "DNS Resolution (DNSX)"

    if ! run_required_stage \
        "DNSX" \
        "$dns_output" \
        run_dnsx "$DOMAIN" "$merged_subdomains" "$dns_output"; then
        return 1
    fi

    # -------------------------------
    # Stage 4: Port Discovery (Naabu) - Placed before web discovery
    # -------------------------------
    print_stage_step 4 "$total_stages" "Port Discovery (Naabu)"

    if ! run_required_stage \
        "Naabu" \
        "$ports_output" \
        run_naabu "$DOMAIN" "$dns_output" "$ports_output"; then
        return 1
    fi

    # -------------------------------
    # Stage 5: HTTP Probing (HTTPX)
    # -------------------------------
    print_stage_step 5 "$total_stages" "HTTP Probing (HTTPX)"

    # Combine resolved domain names and candidate web ports from Naabu
    {
        if [[ -f "$dns_output" ]]; then
            cat "$dns_output"
        fi
        if [[ -f "$web_candidates" ]]; then
            cat "$web_candidates"
        fi
    } | sed '/^$/d' | sort -u > "$http_targets"

    if ! run_required_stage \
        "HTTPX" \
        "$live_output" \
        run_httpx "$DOMAIN" "$http_targets" "$live_output"; then
        return 1
    fi

    if ! run_required_stage \
        "Live URL extraction" \
        "$clean_urls" \
        extract_live_urls "$DOMAIN" "$live_output" "$clean_urls"; then
        return 1
    fi

    # -------------------------------
    # Stage 6: URL Crawling (Katana)
    # -------------------------------
    print_stage_step 6 "$total_stages" "URL Crawling (Katana)"

    if ! run_required_stage \
        "Katana" \
        "$katana_output" \
        run_katana "$DOMAIN" "$clean_urls" "$katana_output"; then
        return 1
    fi

    # -------------------------------
    # Stage 7: Vulnerability Detection (Nuclei)
    # -------------------------------
    print_stage_step 7 "$total_stages" "Vulnerability Detection (Nuclei)"

    if ! run_required_stage \
        "Nuclei" \
        "$nuclei_output" \
        run_nuclei "$DOMAIN" "$katana_output" "$nuclei_output"; then
        return 1
    fi

    # -------------------------------
    # Stage 8: Reporting (Summary & HTML)
    # -------------------------------
    print_stage_step 8 "$total_stages" "Report Generation"

    generate_reports "$workspace" "$DOMAIN"

    log_success "Reconnaissance completed successfully for $DOMAIN"
    return 0

}

main
exit $?
