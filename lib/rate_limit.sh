#!/usr/bin/env bash

# ============================================
# Recon Framework - Rate Limiting
# ============================================

RATE_LIMIT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v log_error >/dev/null 2>&1; then
    # shellcheck source=./logger.sh
    source "$RATE_LIMIT_LIB_DIR/logger.sh"
fi
if ! command -v command_exists >/dev/null 2>&1; then
    # shellcheck source=./helpers.sh
    source "$RATE_LIMIT_LIB_DIR/helpers.sh"
fi
if ! command -v normalize_naabu_ports >/dev/null 2>&1; then
    # shellcheck source=./validation.sh
    source "$RATE_LIMIT_LIB_DIR/validation.sh"
fi

# Global rate limit state
declare -A RATE_LIMIT_RPS=()
declare -A RATE_LIMIT_BURST=()
RATE_LIMIT_CONFIGURED=0

# Default rate limits (requests per second)
RATE_LIMIT_DEFAULTS=(
    "subfinder:2"
    "assetfinder:5"
    "dnsx:50"
    "naabu:100"
    "httpx:5"
    "katana:3"
    "nuclei:3"
)

# Configure rate limits from configuration
rate_limit_configure() {
    local force="${1:-0}"
    if [[ "$RATE_LIMIT_CONFIGURED" -eq 1 && "$force" -ne 1 ]]; then
        return 0
    fi

    # Load defaults
    local default
    for default in "${RATE_LIMIT_DEFAULTS[@]}"; do
        local tool="${default%%:*}"
        local rps="${default##*:}"
        RATE_LIMIT_RPS["$tool"]="$rps"
        RATE_LIMIT_BURST["$tool"]="$rps"
    done

    # Override from environment/config if provided
    # Global rate limit (applies to all tools unless overridden)
    if [[ -n "${RATE_LIMIT_GLOBAL:-}" ]]; then
        if [[ "$RATE_LIMIT_GLOBAL" =~ ^[0-9]+$ ]] && (( RATE_LIMIT_GLOBAL > 0 )); then
            for tool in "${!RATE_LIMIT_RPS[@]}"; do
                RATE_LIMIT_RPS["$tool"]="$RATE_LIMIT_GLOBAL"
                RATE_LIMIT_BURST["$tool"]="$RATE_LIMIT_GLOBAL"
            done
        else
            log_warn "Invalid RATE_LIMIT_GLOBAL: $RATE_LIMIT_GLOBAL (must be positive integer)"
        fi
    fi

    # Per-tool overrides
    local tool
    for tool in "${!RATE_LIMIT_RPS[@]}"; do
        local var_name="RATE_LIMIT_${tool^^}"
        var_name="${var_name//-/_}"
        if [[ -n "${!var_name:-}" ]]; then
            if [[ "${!var_name}" =~ ^[0-9]+$ ]] && (( ${!var_name} > 0 )); then
                RATE_LIMIT_RPS["$tool"]="${!var_name}"
                RATE_LIMIT_BURST["$tool"]="${!var_name}"
            else
                log_warn "Invalid $var_name: ${!var_name} (must be positive integer)"
            fi
        fi
    done

    RATE_LIMIT_CONFIGURED=1
    return 0
}

# Reset rate limit configuration cache
rate_limit_reset() {
    RATE_LIMIT_CONFIGURED=0
    RATE_LIMIT_RPS=()
    RATE_LIMIT_BURST=()
}

# Get rate limit for a tool (requests per second)
rate_limit_get_rps() {
    local tool="$1"
    rate_limit_configure
    printf '%s' "${RATE_LIMIT_RPS[$tool]:-0}"
}

# Get burst limit for a tool
rate_limit_get_burst() {
    local tool="$1"
    rate_limit_configure
    printf '%s' "${RATE_LIMIT_BURST[$tool]:-0}"
}

# Validate rate limit configuration
rate_limit_validate() {
    # Validate raw environment variables if set
    if [[ -n "${RATE_LIMIT_GLOBAL:-}" ]]; then
        if [[ ! "$RATE_LIMIT_GLOBAL" =~ ^[0-9]+$ ]] || (( RATE_LIMIT_GLOBAL <= 0 )); then
            log_error "Invalid RATE_LIMIT_GLOBAL: $RATE_LIMIT_GLOBAL (must be positive integer)"
            return 1
        fi
    fi

    local default tool var_name val
    for default in "${RATE_LIMIT_DEFAULTS[@]}"; do
        tool="${default%%:*}"
        var_name="RATE_LIMIT_${tool^^}"
        var_name="${var_name//-/_}"
        val="${!var_name:-}"
        if [[ -n "$val" ]]; then
            if [[ ! "$val" =~ ^[0-9]+$ ]] || (( val <= 0 )); then
                log_error "Invalid rate limit for $tool ($var_name): $val (must be positive integer)"
                return 1
            fi
        fi
    done

    rate_limit_configure 1

    for tool in "${!RATE_LIMIT_RPS[@]}"; do
        local rps="${RATE_LIMIT_RPS[$tool]}"
        if [[ ! "$rps" =~ ^[0-9]+$ ]] || (( rps <= 0 )); then
            log_error "Invalid rate limit for $tool: $rps (must be positive integer)"
            return 1
        fi
    done
    return 0
}

# Print current rate limit configuration (for debugging)
rate_limit_print_config() {
    rate_limit_configure
    local tool
    for tool in "${!RATE_LIMIT_RPS[@]}"; do
        printf '%s: %s req/s (burst: %s)\n' "$tool" "${RATE_LIMIT_RPS[$tool]}" "${RATE_LIMIT_BURST[$tool]}"
    done
}

# Apply rate limit to a command using native tool flags where possible
# Usage: rate_limit_apply <tool> <command...>
rate_limit_apply() {
    local tool="$1"
    shift
    local cmd=("$@")

    rate_limit_configure

    local rps
    rps="$(rate_limit_get_rps "$tool")"

    # If rate limit is 0 or not set, run without rate limiting
    if [[ -z "$rps" || "$rps" -eq 0 ]]; then
        "${cmd[@]}"
        return $?
    fi

    # If the command already specifies a rate or rate-limit flag, execute directly
    local has_rate_flag=0
    local arg
    for arg in "${cmd[@]}"; do
        if [[ "$arg" == "-rate" || "$arg" == "-rate-limit" ]]; then
            has_rate_flag=1
            break
        fi
    done

    if [[ "$has_rate_flag" -eq 1 ]]; then
        "${cmd[@]}"
        return $?
    fi

    case "$tool" in
        subfinder)
            # subfinder supports -rate-limit
            "${cmd[@]}" -rate-limit "$rps"
            ;;
        assetfinder)
            # assetfinder doesn't have native rate limiting
            # Use external rate limiting if needed
            "${cmd[@]}"
            ;;
        dnsx)
            # dnsx supports -rate-limit
            "${cmd[@]}" -rate-limit "$rps"
            ;;
        naabu)
            # naabu supports -rate
            "${cmd[@]}" -rate "$rps"
            ;;
        httpx)
            # httpx supports -rate-limit
            "${cmd[@]}" -rate-limit "$rps"
            ;;
        katana)
            # katana supports -rate-limit
            "${cmd[@]}" -rate-limit "$rps"
            ;;
        nuclei)
            # nuclei supports -rate-limit
            "${cmd[@]}" -rate-limit "$rps"
            ;;
        *)
            # Unknown tool, run without rate limiting
            log_warn "No rate limit integration for tool: $tool"
            "${cmd[@]}"
            ;;
    esac
}

# Initialize rate limit config from CLI args (for backward compatibility)
rate_limit_init_from_cli() {
    # Global rate limit from --rate-limit
    if [[ -n "${DEFAULT_RATE_LIMIT:-}" ]]; then
        if [[ "$DEFAULT_RATE_LIMIT" =~ ^[0-9]+$ ]] && (( DEFAULT_RATE_LIMIT > 0 )); then
            export RATE_LIMIT_GLOBAL="$DEFAULT_RATE_LIMIT"
        fi
    fi

    # Individual tool rate limits from environment
    if [[ -n "${NAABU_RATE:-}" ]]; then
        export RATE_LIMIT_NAABU="$NAABU_RATE"
    fi
    if [[ -n "${HTTPX_RATE_LIMIT:-}" ]]; then
        export RATE_LIMIT_HTTPX="$HTTPX_RATE_LIMIT"
    fi
    if [[ -n "${NUCLEI_RATE_LIMIT:-}" ]]; then
        export RATE_LIMIT_NUCLEI="$NUCLEI_RATE_LIMIT"
    fi
    if [[ -n "${DNSX_RATE_LIMIT:-}" ]]; then
        export RATE_LIMIT_DNSX="$DNSX_RATE_LIMIT"
    fi
}