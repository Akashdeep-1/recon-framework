#!/usr/bin/env bash

# ============================================
# Recon Framework
# Author : Akashdeep Singh
# Version: 1.2.0
# ============================================

# -------------------------------
# Base Directory
# -------------------------------

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -------------------------------
# Load Configuration
# -------------------------------

source "$BASE_DIR/config.sh"

# -------------------------------
# Load Libraries
# -------------------------------

source "$BASE_DIR/lib/logger.sh"
source "$BASE_DIR/lib/helpers.sh"
source "$BASE_DIR/lib/filesystem.sh"
source "$BASE_DIR/lib/validation.sh"
source "$BASE_DIR/lib/plugins.sh"

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

./recon.sh -d domain.com

Options:

-d      Target Domain
-h      Help

Example:

./recon.sh -d example.com

EOF

}


# -------------------------------
# Parse Arguments
# -------------------------------

DOMAIN=""

while getopts ":d:h" opt
do

    case "$opt" in

        d)
            DOMAIN="$OPTARG"
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

if [[ -z "$DOMAIN" ]]
then

    print_banner
    log_error "No target domain supplied."
    usage
    exit 1

fi


if ! validate_domain "$DOMAIN"
then
    exit 1
fi


# -------------------------------
# Main
# -------------------------------

run_required_stage() {

    local stage_name="$1"
    local stage_status

    shift

    "$@"
    stage_status=$?

    if [[ "$stage_status" -eq 0 ]]; then
        return 0
    fi

    log_error "$stage_name failed. Reconnaissance aborted."
    return "$stage_status"
}


main() {

    print_banner

    log_info "Target : $DOMAIN"

    if ! create_workspace "$DOMAIN"; then
        log_error "Framework failed: unable to create workspace for $DOMAIN"
        return 1
    fi

    local workspace="${OUTPUT_DIR}/${DOMAIN}"
    local subdomain_dir="${workspace}/subdomains"

    local subfinder_output="${subdomain_dir}/subfinder.txt"
    local assetfinder_output="${subdomain_dir}/assetfinder.txt"

    local dns_output="${workspace}/dns/resolved.txt"
    local live_output="${workspace}/live/httpx.txt"
    local clean_urls="${workspace}/live/urls.txt"
    local katana_output="${workspace}/urls/katana.txt"
    local nuclei_output="${workspace}/nuclei/findings.jsonl"
    local ports_output="${workspace}/ports/naabu.txt"

    log_success "Framework Started"


    # -------------------------------
    # Subdomain Enumeration
    # -------------------------------

    if ! run_required_stage \
        "Subfinder" \
        run_subfinder "$DOMAIN" "$subfinder_output"; then
        return 1
    fi

    if ! run_required_stage \
        "Assetfinder" \
        run_assetfinder "$DOMAIN" "$assetfinder_output"; then
        return 1
    fi

    if ! run_required_stage \
        "Subdomain merge" \
        merge_subdomains "$subdomain_dir" "$DOMAIN"; then
        return 1
    fi


    # -------------------------------
    # DNS Resolution
    # -------------------------------

    if ! run_required_stage \
        "DNSX" \
        run_dnsx "${subdomain_dir}/all.txt" "$dns_output"; then
        return 1
    fi


    # -------------------------------
    # HTTP Probing
    # -------------------------------

    if ! run_required_stage \
        "HTTPX" \
        run_httpx "$dns_output" "$live_output"; then
        return 1
    fi


    # -------------------------------
    # URL Extraction
    # -------------------------------

    if ! run_required_stage \
        "Live URL extraction" \
        extract_live_urls "$live_output" "$clean_urls"; then
        return 1
    fi


    # -------------------------------
    # URL Crawling
    # -------------------------------

    if ! run_required_stage \
        "Katana" \
        run_katana "$clean_urls" "$katana_output"; then
        return 1
    fi


    # -------------------------------
    # Vulnerability Detection
    # -------------------------------

    if ! run_required_stage \
        "Nuclei" \
        run_nuclei "$katana_output" "$nuclei_output"; then
        return 1
    fi


    # -------------------------------
    # Port Discovery
    # -------------------------------

    if ! run_required_stage \
        "Naabu" \
        run_naabu "$dns_output" "$ports_output"; then
        return 1
    fi


    log_success "Reconnaissance completed successfully for $DOMAIN"
    return 0

}

main
exit $?
