#!/usr/bin/env bash

# ============================================
# Recon Framework - Progress Library
# ============================================

PROGRESS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v log_info >/dev/null 2>&1; then
    # shellcheck source=./logger.sh
    source "$PROGRESS_LIB_DIR/logger.sh"
fi

# Print a stage progress banner with step counter
print_stage_step() {
    local step_current="$1"
    local step_total="$2"
    local stage_name="$3"

    echo ""
    log_info "=== [Stage ${step_current}/${step_total}] ${stage_name} ==="
}
