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

# -------------------------------
# Main
# -------------------------------

main() {

    print_banner

    log_info "Target : $DOMAIN"

    create_workspace "$DOMAIN"

    log_success "Framework Started"

}
main
