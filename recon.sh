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

main() {

    print_banner

    log_info "Target : $DOMAIN"

    create_workspace "$DOMAIN"

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

    run_subfinder "$DOMAIN" "$subfinder_output"

    run_assetfinder "$DOMAIN" "$assetfinder_output"

    merge_subdomains "$subdomain_dir"


    # -------------------------------
    # DNS Resolution
    # -------------------------------

    run_dnsx \
        "${subdomain_dir}/all.txt" \
        "$dns_output"


    # -------------------------------
    # HTTP Probing
    # -------------------------------

    run_httpx \
        "$dns_output" \
        "$live_output"


    # -------------------------------
    # URL Extraction
    # -------------------------------

    extract_live_urls \
        "$live_output" \
        "$clean_urls"


    # -------------------------------
    # URL Crawling
    # -------------------------------

    run_katana \
        "$clean_urls" \
        "$katana_output"


    # -------------------------------
    # Vulnerability Detection
    # -------------------------------

    run_nuclei \
        "$clean_urls" \
        "$nuclei_output"


    # -------------------------------
    # Port Discovery
    # -------------------------------

    run_naabu \
        "$dns_output" \
        "$ports_output"


    log_success "Reconnaissance completed for $DOMAIN"

}

main
