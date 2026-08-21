#!/usr/bin/env bash

# ============================================
# Recon Framework - Filesystem Library
# ============================================

# Create the directory structure for a scan
create_workspace() {

    local domain="$1"
    local base_dir="${OUTPUT_DIR}/${domain}"
    local directory
    local directories=(
        "$base_dir"
        "$base_dir/subdomains"
        "$base_dir/dns"
        "$base_dir/live"
        "$base_dir/ports"
        "$base_dir/urls"
        "$base_dir/js"
        "$base_dir/screenshots"
        "$base_dir/nuclei"
        "$base_dir/reports"
        "$base_dir/logs"
    )

    for directory in "${directories[@]}"; do
        if ! create_directory "$directory"; then
            log_error "Failed to create workspace directory: $directory"
            return 1
        fi
    done

    log_success "Workspace created: $base_dir"
    return 0
}
