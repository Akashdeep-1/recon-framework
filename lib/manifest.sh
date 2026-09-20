#!/usr/bin/env bash

# ============================================
# Recon Framework - Manifest & Pipeline State
# ============================================

MANIFEST_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v log_debug >/dev/null 2>&1; then
    # shellcheck source=./logger.sh
    source "$MANIFEST_LIB_DIR/logger.sh"
fi

# Canonical stages list
MANIFEST_CANONICAL_STAGES=("subdomains" "dns" "ports" "live" "crawling" "vuln" "reports")

# Initialize manifest.json for a workspace
init_manifest() {
    local workspace="$1"
    local domain="$2"
    local threads="${3:-50}"
    local rate_limit="${4:-150}"
    local timeout="${5:-300}"
    local retries="${6:-1}"
    local resume_val="${7:-0}"
    local stages_sel="${8:-all}"
    local stages_skip="${9:-}"

    local manifest_file="${workspace}/manifest.json"
    local start_time
    start_time="$(date +"%Y-%m-%d %H:%M:%S" 2>/dev/null || date)"

    local resume_bool="false"
    if [[ "$resume_val" == "1" || "$resume_val" == "true" ]]; then
        resume_bool="true"
    fi

    # Build initial JSON
    {
        printf '{\n'
        printf '  "target": "%s",\n' "$domain"
        printf '  "start_time": "%s",\n' "$start_time"
        printf '  "end_time": null,\n'
        printf '  "status": "running",\n'
        printf '  "config": {\n'
        printf '    "threads": %d,\n' "$threads"
        printf '    "rate_limit": %d,\n' "$rate_limit"
        printf '    "timeout": %d,\n' "$timeout"
        printf '    "retries": %d,\n' "$retries"
        printf '    "resume": %s,\n' "$resume_bool"
        printf '    "stages_selected": "%s",\n' "$stages_sel"
        printf '    "stages_skipped": "%s"\n' "$stages_skip"
        printf '  },\n'
        printf '  "stages": {\n'

        local i=0
        local total=${#MANIFEST_CANONICAL_STAGES[@]}
        for s in "${MANIFEST_CANONICAL_STAGES[@]}"; do
            i=$(( i + 1 ))
            printf '    "%s": { "status": "pending", "duration_seconds": 0, "output_count": 0, "attempts": 0 }' "$s"
            if (( i < total )); then
                printf ',\n'
            else
                printf '\n'
            fi
        done

        printf '  }\n'
        printf '}\n'
    } > "$manifest_file"

    log_debug "Initialized manifest: $manifest_file"
    return 0
}

# Update a single stage status in manifest.json
# Usage: update_stage_manifest "$workspace" "$stage" "$status" [duration_seconds] [output_count] [attempts]
update_stage_manifest() {
    local workspace="$1"
    local stage="$2"
    local status="$3"
    local duration="${4:-0}"
    local count="${5:-0}"
    local attempts="${6:-1}"

    local manifest_file="${workspace}/manifest.json"
    if [[ ! -f "$manifest_file" ]]; then
        return 0
    fi

    # Read existing target, start_time, config, etc.
    # To be fast and robust in pure bash without jq dependency:
    local temp_manifest
    temp_manifest="$(mktemp "${manifest_file}.tmp.XXXXXX" 2>/dev/null || printf '%s.tmp' "$manifest_file")"

    # Replace stage entry line matching: "stage": { ... }
    sed -E "s/\"${stage}\":[[:space:]]*\{[^\}]*\}/\"${stage}\": { \"status\": \"${status}\", \"duration_seconds\": ${duration}, \"output_count\": ${count}, \"attempts\": ${attempts} }/" "$manifest_file" > "$temp_manifest"
    mv -f "$temp_manifest" "$manifest_file"

    log_debug "Manifest updated: stage '$stage' -> '$status' (duration: ${duration}s, count: $count, attempts: $attempts)"
    return 0
}

# Finalize manifest with overall status and completion timestamp
finalize_manifest() {
    local workspace="$1"
    local overall_status="$2"

    local manifest_file="${workspace}/manifest.json"
    if [[ ! -f "$manifest_file" ]]; then
        return 0
    fi

    local end_time
    end_time="$(date +"%Y-%m-%d %H:%M:%S" 2>/dev/null || date)"

    local temp_manifest
    temp_manifest="$(mktemp "${manifest_file}.tmp.XXXXXX" 2>/dev/null || printf '%s.tmp' "$manifest_file")"

    sed -E \
        -e "s/\"end_time\":[[:space:]]*null/\"end_time\": \"${end_time}\"/" \
        -e "s/\"status\":[[:space:]]*\"running\"/\"status\": \"${overall_status}\"/" \
        "$manifest_file" > "$temp_manifest"

    mv -f "$temp_manifest" "$manifest_file"

    log_debug "Finalized manifest: status '$overall_status', end_time: $end_time"
    return 0
}
