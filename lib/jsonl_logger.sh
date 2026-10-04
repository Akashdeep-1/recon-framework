#!/usr/bin/env bash

# ============================================
# Recon Framework - Structured JSONL Logging
# ============================================

JSONL_LOGGER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v log_error >/dev/null 2>&1; then
    # shellcheck source=./logger.sh
    source "$JSONL_LOGGER_LIB_DIR/logger.sh"
fi
if ! command -v command_exists >/dev/null 2>&1; then
    # shellcheck source=./helpers.sh
    source "$JSONL_LOGGER_LIB_DIR/helpers.sh"
fi

# Global JSONL state
JSONL_RUN_ID=""
JSONL_LOG_FILE=""
JSONL_ENABLED=1

# Redaction patterns for credentials
JSONL_REDACT_PATTERNS=(
    # Authorization headers
    'Authorization:[[:space:]]*Bearer[[:space:]]+[^[:space:]]+'
    'Authorization:[[:space:]]*Basic[[:space:]]+[^[:space:]]+'
    'Authorization:[[:space:]]*[^[:space:]]+'
    # API keys in various formats
    'api[_-]?key[[:space:]]*[:=][[:space:]]*[^[:space:]]+'
    'apikey[[:space:]]*[:=][[:space:]]*[^[:space:]]+'
    # Passwords
    'password[[:space:]]*[:=][[:space:]]*[^[:space:]]+'
    'passwd[[:space:]]*[:=][[:space:]]*[^[:space:]]+'
    # Generic secrets
    'secret[[:space:]]*[:=][[:space:]]*[^[:space:]]+'
    'token[[:space:]]*[:=][[:space:]]*[^[:space:]]+'
    # Cookies
    'cookie[[:space:]]*[:=][[:space:]]*[^[:space:]]+'
    'session[[:space:]]*[:=][[:space:]]*[^[:space:]]+'
    # OAuth
    'access_token[[:space:]]*[:=][[:space:]]*[^[:space:]]+'
    'refresh_token[[:space:]]*[:=][[:space:]]*[^[:space:]]+'
    'client_secret[[:space:]]*[:=][[:space:]]*[^[:space:]]+'
)

# Generate a run ID (UUID-like)
jsonl_generate_run_id() {
    local ts
    ts="$(date +%s%N 2>/dev/null || date +%s)"
    local rand
    rand="$RANDOM$RANDOM$RANDOM"
    printf 'run-%s-%s' "$ts" "$rand"
}

# Initialize JSONL logging for a run
jsonl_init() {
    local run_id="${1:-}"
    local log_file="${2:-}"

    if [[ "$JSONL_ENABLED" -ne 1 ]]; then
        return 0
    fi

    JSONL_RUN_ID="${run_id:-$(jsonl_generate_run_id)}"

    if [[ -n "$log_file" ]]; then
        JSONL_LOG_FILE="$log_file"
        # Ensure directory exists
        local log_dir
        log_dir="$(dirname "$log_file")"
        if [[ ! -d "$log_dir" ]]; then
            mkdir -p "$log_dir" 2>/dev/null || true
        fi
        # Touch the file
        : > "$JSONL_LOG_FILE" 2>/dev/null || true
    fi

    # Emit run_start event
    jsonl_emit "run_start" "status" "started" "timestamp" "$(jsonl_timestamp)"
    return 0
}

# Get current timestamp in ISO 8601 format
jsonl_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%S.%3NZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Escape string for JSON
jsonl_escape() {
    local str="$1"
    # Escape backslashes first
    str="${str//\\/\\\\}"
    # Escape double quotes
    str="${str//\"/\\\"}"
    # Escape newlines
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    printf '%s' "$str"
}

# Redact credentials from a string
jsonl_redact() {
    local input="$1"
    local output="$input"
    local pattern

    for pattern in "${JSONL_REDACT_PATTERNS[@]}"; do
        output="$(printf '%s' "$output" | sed -E "s/$pattern/[REDACTED]/gi")"
    done

    # Also redact common patterns like key=value in URLs
    output="$(printf '%s' "$output" | sed -E 's/([?&])(api[_-]?key|password|secret|token|token|access_token|refresh_token|client_secret|password)=([^&]+)/\1\2=[REDACTED]/gi')"

    printf '%s' "$output"
}

# Emit a JSONL event
jsonl_emit() {
    if [[ "$JSONL_ENABLED" -ne 1 ]]; then
        return 0
    fi

    local event_type="$1"
    shift

    local timestamp
    timestamp="$(jsonl_timestamp)"

    # Build JSON object
    local json="{"
    json="${json}\"event\":\"$(jsonl_escape "$event_type")\","
    json="${json}\"run_id\":\"$(jsonl_escape "$JSONL_RUN_ID")\","
    json="${json}\"timestamp\":\"$timestamp\""

    # Add remaining key-value pairs
    local key value
    while [[ $# -gt 0 ]]; do
        key="$1"
        value="$2"
        shift 2

        # Redact sensitive data from values
        value="$(jsonl_redact "$value")"

        json="${json},\"$(jsonl_escape "$key")\":\"$(jsonl_escape "$value")\""
    done

    json="${json}}"

    # Output to log file if configured
    if [[ -n "$JSONL_LOG_FILE" ]]; then
        printf '%s\n' "$json" >> "$JSONL_LOG_FILE" 2>/dev/null || true
    fi

    # Also output to stdout if VERBOSE or if explicitly requested
    if [[ "${JSONL_STDOUT:-0}" -eq 1 ]]; then
        printf '%s\n' "$json"
    fi

    return 0
}

# Convenience functions for common events
jsonl_run_start() {
    local target="${1:-}"
    jsonl_emit "run_start" "target" "$target" "version" "${FRAMEWORK_VERSION:-unknown}"
}

jsonl_run_complete() {
    local status="${1:-success}"
    local duration_ms="${2:-0}"
    local targets_count="${3:-0}"
    jsonl_emit "run_complete" "status" "$status" "duration_ms" "$duration_ms" "targets_count" "$targets_count"
}

jsonl_stage_start() {
    local stage="$1"
    local target="${2:-}"
    jsonl_emit "stage_start" "stage" "$stage" "target" "$target"
}

jsonl_stage_complete() {
    local stage="$1"
    local status="${2:-success}"
    local duration_ms="${3:-0}"
    local assets_count="${4:-0}"
    jsonl_emit "stage_complete" "stage" "$stage" "status" "$status" "duration_ms" "$duration_ms" "assets_count" "$assets_count"
}

# Phase 7.3: Conditional execution telemetry
jsonl_stage_skipped() {
    local stage="$1"
    local reason="${2:-condition_false}"
    local condition="${3:-}"
    jsonl_emit "stage_skipped" "stage" "$stage" "reason" "$reason" "condition" "$condition"
}

jsonl_stage_blocked() {
    local stage="$1"
    local blocked_by="${2:-}"
    jsonl_emit "stage_blocked" "stage" "$stage" "blocked_by" "$blocked_by"
}

jsonl_stage_ready() {
    local stage="$1"
    local condition="${2:-}"
    jsonl_emit "stage_ready" "stage" "$stage" "condition" "$condition"
}

jsonl_condition_evaluated() {
    local stage="$1"
    local condition="${2:-}"
    local result="${3:-false}"
    jsonl_emit "condition_evaluated" "stage" "$stage" "condition" "$condition" "result" "$result"
}

# Phase 7.4: Parallel execution telemetry
jsonl_stage_queued() {
    local stage="$1"
    local parallel_group="${2:-}"
    local deps_satisfied="${3:-}"
    jsonl_emit "stage_queued" "stage" "$stage" "parallel_group" "$parallel_group" "deps_satisfied" "$deps_satisfied"
}

jsonl_parallel_start() {
    local concurrency="$1"
    local run_id="${2:-$JSONL_RUN_ID}"
    jsonl_emit "parallel_start" "max_concurrency" "$concurrency" "run_id" "$run_id"
}

jsonl_parallel_complete() {
    local completed_stages="$1"
    local run_id="${2:-$JSONL_RUN_ID}"
    jsonl_emit "parallel_complete" "completed_stages" "$completed_stages" "run_id" "$run_id"
}

jsonl_tool_start() {
    local tool="$1"
    local stage="${2:-}"
    local target="${3:-}"
    jsonl_emit "tool_start" "tool" "$tool" "stage" "$stage" "target" "$target"
}

jsonl_tool_complete() {
    local tool="$1"
    local stage="${2:-}"
    local status="${3:-success}"
    local duration_ms="${4:-0}"
    local output_count="${5:-0}"
    jsonl_emit "tool_complete" "tool" "$tool" "stage" "$stage" "status" "$status" "duration_ms" "$duration_ms" "output_count" "$output_count"
}

jsonl_tool_error() {
    local tool="$1"
    local stage="${2:-}"
    local error_msg="${3:-unknown error}"
    local duration_ms="${4:-0}"
    jsonl_emit "tool_error" "tool" "$tool" "stage" "$stage" "error" "$error_msg" "duration_ms" "$duration_ms"
}

jsonl_scope_rejection() {
    local type="$1"  # domain or url
    local value="$2"
    local target="${3:-}"
    jsonl_emit "scope_rejection" "type" "$type" "value" "$value" "target" "$target"
}

jsonl_config_validation() {
    local status="$1"
    local issues="${2:-}"
    jsonl_emit "config_validation" "status" "$status" "issues" "$issues"
}

# Disable JSONL logging (for testing or when not needed)
jsonl_disable() {
    JSONL_ENABLED=0
}

# Enable JSONL logging
jsonl_enable() {
    JSONL_ENABLED=1
}

# Set stdout output for JSONL
jsonl_set_stdout() {
    local enabled="${1:-1}"
    JSONL_STDOUT="$enabled"
}

# Get current run ID
jsonl_get_run_id() {
    printf '%s' "$JSONL_RUN_ID"
}

# Get current log file
jsonl_get_log_file() {
    printf '%s' "$JSONL_LOG_FILE"
}