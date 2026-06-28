#!/usr/bin/env bash

# ============================================
# Recon Framework - Filesystem Library
# ============================================

# Create the directory structure for a scan
create_workspace() {

    local domain="$1"
    local base_dir="${OUTPUT_DIR}/${domain}"

    create_directory "$base_dir"

    create_directory "$base_dir/subdomains"
    create_directory "$base_dir/dns"
    create_directory "$base_dir/live"
    create_directory "$base_dir/ports"
    create_directory "$base_dir/urls"
    create_directory "$base_dir/js"
    create_directory "$base_dir/screenshots"
    create_directory "$base_dir/nuclei"
    create_directory "$base_dir/reports"
    create_directory "$base_dir/logs"

    log_success "Workspace created: $base_dir"
}
