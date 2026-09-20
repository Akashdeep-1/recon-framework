#!/usr/bin/env bash

# ============================================
# Recon Framework - Logger Library
# ============================================

# Load configuration if it hasn't been loaded yet.
LOGGER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${RESET:-}" ]]; then
    # shellcheck source=../config.sh
    source "$LOGGER_LIB_DIR/../config.sh"
fi

# Internal helper to log to stdout and optionally to LOG_FILE
_log_message() {
    local level="$1"
    local color="$2"
    local message="$3"

    echo -e "${color}[${level}]${RESET} ${message}"

    if [[ -n "${LOG_FILE:-}" ]]; then
        local ts
        ts="$(date +"%Y-%m-%d %H:%M:%S" 2>/dev/null || date)"
        # Strip ANSI escape sequences from message for persistent log file
        local clean_msg
        clean_msg="$(printf '%b' "$message" | sed -E 's/\x1B\[[0-9;]*[mK]//g')"
        printf '[%s] [%-7s] %s\n' "$ts" "$level" "$clean_msg" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

# Print an informational message.
log_info() {
    local message="$1"
    _log_message "INFO" "${BLUE}" "${message}"
}

# Print a success message.
log_success() {
    local message="$1"
    _log_message "SUCCESS" "${GREEN}" "${message}"
}

# Print a warning message.
log_warn() {
    local message="$1"
    _log_message "WARNING" "${YELLOW}" "${message}"
}

# Print an error message.
log_error() {
    local message="$1"
    _log_message "ERROR" "${RED}" "${message}"
}

# Print a debug message (always logged to file if set, printed to console only if VERBOSE=1).
log_debug() {
    local message="$1"
    if [[ "${VERBOSE:-0}" == "1" ]]; then
        _log_message "DEBUG" "${CYAN}" "${message}"
    elif [[ -n "${LOG_FILE:-}" ]]; then
        local ts clean_msg
        ts="$(date +"%Y-%m-%d %H:%M:%S" 2>/dev/null || date)"
        clean_msg="$(printf '%b' "$message" | sed -E 's/\x1B\[[0-9;]*[mK]//g')"
        printf '[%s] [%-7s] %s\n' "$ts" "DEBUG" "$clean_msg" >> "$LOG_FILE" 2>/dev/null || true
    fi
}
