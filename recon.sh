#!/usr/bin/env bash

# ============================================
# Recon Framework
# Author : Akashdeep Singh
# Version: 1.0.0
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
cat << "EOF"

██████╗ ███████╗ ██████╗ ██████╗ ███╗   ██╗
██╔══██╗██╔════╝██╔════╝██╔═══██╗████╗  ██║
██████╔╝█████╗  ██║     ██║   ██║██╔██╗ ██║
██╔══██╗██╔══╝  ██║     ██║   ██║██║╚██╗██║
██║  ██║███████╗╚██████╗╚██████╔╝██║ ╚████║
╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝

        Recon Framework v1.0

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

Options

-d      Target Domain
-h      Help

Example

./recon.sh -d tesla.com

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
# Validate
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
local subdomain_output="${subdomain_dir}/subfinder.txt"
local assetfinder_output="${subdomain_dir}/assetfinder.txt"

log_success "Framework Started"

run_subfinder "$DOMAIN" "$subdomain_output"

run_assetfinder "$DOMAIN" "$assetfinder_output"

merge_subdomains "$subdomain_dir"
local dns_output="${workspace}/dns/resolved.txt"

run_dnsx "${subdomain_dir}/all.txt" "$dns_output"

local live_output="${workspace}/live/httpx.txt"

run_httpx "$dns_output" "$live_output"
local clean_urls="${workspace}/live/urls.txt"
local katana_output="${workspace}/urls/katana.txt"

extract_live_urls "$live_output" "$clean_urls"

run_katana "$clean_urls" "$katana_output"
local nuclei_output="${workspace}/nuclei/findings.jsonl"

run_nuclei "$clean_urls" "$nuclei_output"
local ports_output="${workspace}/ports/naabu.txt"

run_naabu "$dns_output" "$ports_output"

}
main
