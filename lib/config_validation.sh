#!/usr/bin/env bash

# ============================================
# Recon Framework - Configuration Validation
# ============================================

CONFIG_VALIDATION_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v log_error >/dev/null 2>&1; then
    # shellcheck source=./logger.sh
    source "$CONFIG_VALIDATION_LIB_DIR/logger.sh"
fi
if ! command -v command_exists >/dev/null 2>&1; then
    # shellcheck source=./helpers.sh
    source "$CONFIG_VALIDATION_LIB_DIR/helpers.sh"
fi
if ! command -v normalize_domain >/dev/null 2>&1; then
    # shellcheck source=./validation.sh
    source "$CONFIG_VALIDATION_LIB_DIR/validation.sh"
fi
if ! command -v normalize_naabu_ports >/dev/null 2>&1; then
    # shellcheck source=./validation.sh
    source "$CONFIG_VALIDATION_LIB_DIR/validation.sh"
fi

# Configuration validation results
CONFIG_VALIDATION_ERRORS=()
CONFIG_VALIDATION_WARNINGS=()

# Validate all configuration before execution
config_validate_all() {
    CONFIG_VALIDATION_ERRORS=()
    CONFIG_VALIDATION_WARNINGS=()

    config_validate_targets
    config_validate_scope
    config_validate_output_paths
    config_validate_workspace_paths
    config_validate_tool_config
    config_validate_rate_limits
    config_validate_timeouts
    config_validate_concurrency
    config_validate_required_binaries
    config_validate_incompatible_options

    # Emit validation events if JSONL is available
    if command -v jsonl_config_validation >/dev/null 2>&1; then
        if [[ ${#CONFIG_VALIDATION_ERRORS[@]} -gt 0 ]]; then
            jsonl_config_validation "failed" "${CONFIG_VALIDATION_ERRORS[*]}"
        elif [[ ${#CONFIG_VALIDATION_WARNINGS[@]} -gt 0 ]]; then
            jsonl_config_validation "warning" "${CONFIG_VALIDATION_WARNINGS[*]}"
        else
            jsonl_config_validation "passed" ""
        fi
    fi

    if [[ ${#CONFIG_VALIDATION_ERRORS[@]} -gt 0 ]]; then
        for err in "${CONFIG_VALIDATION_ERRORS[@]}"; do
            log_error "Config validation: $err"
        done
        return 1
    fi

    if [[ ${#CONFIG_VALIDATION_WARNINGS[@]} -gt 0 ]]; then
        for warn in "${CONFIG_VALIDATION_WARNINGS[@]}"; do
            log_warn "Config validation: $warn"
        done
    fi

    return 0
}

# Validate target configuration
config_validate_targets() {
    if [[ "${SELF_TEST:-0}" -eq 1 ]]; then
        return 0
    fi

    local initial_errors=${#CONFIG_VALIDATION_ERRORS[@]}

    if [[ ${#TARGET_DOMAINS[@]} -eq 0 ]]; then
        CONFIG_VALIDATION_ERRORS+=("No target domains specified (use -d or -l)")
    fi

    local target
    for target in "${TARGET_DOMAINS[@]}"; do
        if ! validate_domain "$target"; then
            CONFIG_VALIDATION_ERRORS+=("Invalid target domain: $target")
        fi
    done

    if [[ ${#CONFIG_VALIDATION_ERRORS[@]} -gt $initial_errors ]]; then
        return 1
    fi
    return 0
}

# Helper to normalize stage name for validation
_normalize_stage() {
    local raw
    raw="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    case "$raw" in
        subdomain|subdomains) echo "subdomains" ;;
        dns|dnsx) echo "dns" ;;
        port|ports|naabu) echo "ports" ;;
        live|httpx|http) echo "live" ;;
        crawling|crawl|crawler|katana|urls) echo "crawling" ;;
        vuln|vulns|nuclei) echo "vuln" ;;
        report|reports|summary) echo "reports" ;;
        *) echo "$raw" ;;
    esac
}

# Validate scope configuration
config_validate_scope() {
    if [[ -n "${CLI_SKIP:-}" ]]; then
        local -a skip_stages=()
        IFS=',' read -r -a skip_stages <<< "$CLI_SKIP"
        local stage norm_stage
        for stage in "${skip_stages[@]}"; do
            stage="${stage// /}"
            [[ -z "$stage" ]] && continue
            norm_stage="$(_normalize_stage "$stage")"
            case "$norm_stage" in
                subdomains|dns|ports|live|crawling|vuln|reports) ;;
                *)
                    CONFIG_VALIDATION_WARNINGS+=("Unknown stage in --skip: $stage")
                    ;;
            esac
        done
    fi

    if [[ -n "${CLI_STAGES:-}" && "${CLI_STAGES}" != "all" ]]; then
        local -a stages=()
        IFS=',' read -r -a stages <<< "$CLI_STAGES"
        local stage norm_stage
        for stage in "${stages[@]}"; do
            stage="${stage// /}"
            [[ -z "$stage" ]] && continue
            norm_stage="$(_normalize_stage "$stage")"
            case "$norm_stage" in
                subdomains|dns|ports|live|crawling|vuln|reports) ;;
                *)
                    CONFIG_VALIDATION_ERRORS+=("Unknown stage in --stages: $stage")
                    ;;
            esac
        done
    fi

    # ENFORCE_STRICT_SCOPE validation
    if [[ "${ENFORCE_STRICT_SCOPE:-true}" != "true" && "${ENFORCE_STRICT_SCOPE:-true}" != "false" ]]; then
        CONFIG_VALIDATION_ERRORS+=("ENFORCE_STRICT_SCOPE must be 'true' or 'false', got: ${ENFORCE_STRICT_SCOPE}")
    fi
}

# Validate output directory paths
config_validate_output_paths() {
    if [[ -z "${OUTPUT_DIR:-}" ]]; then
        CONFIG_VALIDATION_ERRORS+=("OUTPUT_DIR is not set")
        return
    fi

    local parent_dir
    parent_dir="$(dirname "$OUTPUT_DIR")"

    # Check if parent directory exists and is writable
    if [[ ! -d "$parent_dir" ]]; then
        CONFIG_VALIDATION_ERRORS+=("Output directory parent does not exist: $parent_dir")
    elif [[ ! -w "$parent_dir" ]]; then
        CONFIG_VALIDATION_ERRORS+=("Output directory parent is not writable: $parent_dir")
    fi

    # Check if OUTPUT_DIR itself can be created/accessed
    if [[ -e "$OUTPUT_DIR" && ! -d "$OUTPUT_DIR" ]]; then
        CONFIG_VALIDATION_ERRORS+=("OUTPUT_DIR exists but is not a directory: $OUTPUT_DIR")
    fi
}

# Validate workspace paths
config_validate_workspace_paths() {
    local tmpdir="${TMPDIR:-/tmp}"
    if [[ ! -d "$tmpdir" || ! -w "$tmpdir" ]]; then
        CONFIG_VALIDATION_WARNINGS+=("Temporary directory may not be writable: $tmpdir")
    fi
}

# Validate tool configuration
config_validate_tool_config() {
    # NAABU_PORTS
    if ! normalize_naabu_ports "$NAABU_PORTS" >/dev/null 2>&1; then
        CONFIG_VALIDATION_ERRORS+=("Invalid NAABU_PORTS: $NAABU_PORTS (expected a number or top-N)")
    fi

    # WEB_PORTS format
    if [[ -n "${WEB_PORTS:-}" ]]; then
        local IFS=','
        local port
        for port in $WEB_PORTS; do
            if [[ ! "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
                CONFIG_VALIDATION_ERRORS+=("Invalid port in WEB_PORTS: $port")
            fi
        done
    fi

    # Nuclei severity
    if [[ -n "${NUCLEI_SEVERITY:-}" ]]; then
        local valid_severities="info,low,medium,high,critical"
        local IFS=','
        local sev
        for sev in $NUCLEI_SEVERITY; do
            if [[ ! "$valid_severities" == *"$sev"* ]]; then
                CONFIG_VALIDATION_WARNINGS+=("Unknown nuclei severity: $sev (valid: $valid_severities)")
            fi
        done
    fi

    # Nuclei tags - just warn on empty
    if [[ -n "${NUCLEI_TAGS:-}" && -z "$(echo "$NUCLEI_TAGS" | tr -d '[:space:],')" ]]; then
        CONFIG_VALIDATION_WARNINGS+=("NUCLEI_TAGS appears to be empty")
    fi
}

# Validate rate limit values
config_validate_rate_limits() {
    if ! command -v rate_limit_validate >/dev/null 2>&1; then
        return 0
    fi

    if ! rate_limit_validate; then
        CONFIG_VALIDATION_ERRORS+=("Rate limit validation failed")
    fi
}

# Validate timeout values
config_validate_timeouts() {
    if [[ ! "${STAGE_TIMEOUT:-300}" =~ ^[0-9]+$ ]] || (( STAGE_TIMEOUT < 0 )); then
        CONFIG_VALIDATION_ERRORS+=("Invalid STAGE_TIMEOUT: $STAGE_TIMEOUT (must be non-negative integer)")
    fi

    if [[ ! "${STAGE_RETRIES:-1}" =~ ^[0-9]+$ ]]; then
        CONFIG_VALIDATION_ERRORS+=("Invalid STAGE_RETRIES: $STAGE_RETRIES (must be non-negative integer)")
    fi

    if [[ ! "${STAGE_TIMEOUT:-300}" =~ ^[0-9]+$ ]] || (( STAGE_TIMEOUT > 86400 )); then
        CONFIG_VALIDATION_WARNINGS+=("STAGE_TIMEOUT is very high ($STAGE_TIMEOUT seconds)")
    fi

    if [[ ! "${HTTPX_TIMEOUT:-10}" =~ ^[0-9]+$ ]] || (( HTTPX_TIMEOUT < 1 || HTTPX_TIMEOUT > 300 )); then
        CONFIG_VALIDATION_WARNINGS+=("HTTPX_TIMEOUT should be between 1-300 seconds")
    fi

    if [[ ! "${KATANA_TIMEOUT:-10}" =~ ^[0-9]+$ ]] || (( KATANA_TIMEOUT < 1 || KATANA_TIMEOUT > 300 )); then
        CONFIG_VALIDATION_WARNINGS+=("KATANA_TIMEOUT should be between 1-300 seconds")
    fi

    if [[ ! "${NUCLEI_TIMEOUT:-10}" =~ ^[0-9]+$ ]] || (( NUCLEI_TIMEOUT < 1 || NUCLEI_TIMEOUT > 300 )); then
        CONFIG_VALIDATION_WARNINGS+=("NUCLEI_TIMEOUT should be between 1-300 seconds")
    fi
}

# Validate concurrency values
config_validate_concurrency() {
    local -A concurrency_vars=(
        ["DNSX_THREADS"]="1 1000"
        ["HTTPX_THREADS"]="1 500"
        ["KATANA_CONCURRENCY"]="1 100"
        ["NUCLEI_CONCURRENCY"]="1 200"
        ["DEFAULT_THREADS"]="1 1000"
        ["PARALLEL_STAGE_THREADS"]="1 100"
    )

    local var min_val max_val val
    for var in "${!concurrency_vars[@]}"; do
        val="${!var:-}"
        min_val="${concurrency_vars[$var]%% *}"
        max_val="${concurrency_vars[$var]##* }"

        if [[ -n "$val" ]]; then
            if [[ ! "$val" =~ ^[0-9]+$ ]] || (( val < min_val || val > max_val )); then
                CONFIG_VALIDATION_WARNINGS+=("$var=$val out of recommended range ($min_val-$max_val)")
            fi
        fi
    done

    # Check for excessive global concurrency
    local total_threads=0
    for var in DNSX_THREADS HTTPX_THREADS KATANA_CONCURRENCY NUCLEI_CONCURRENCY; do
        val="${!var:-}"
        if [[ -n "$val" && "$val" =~ ^[0-9]+$ ]]; then
            total_threads=$(( total_threads + val ))
        fi
    done
    if (( total_threads > 2000 )); then
        CONFIG_VALIDATION_WARNINGS+=("Total concurrency ($total_threads) is very high, may cause resource exhaustion")
    fi
}

# Validate required binaries
config_validate_required_binaries() {
    local -a required_binaries=(
        "bash:bash"
        "mkdir:coreutils"
        "awk:gawk"
        "sed:sed"
        "grep:grep"
        "sort:coreutils"
        "awk:gawk"
        "date:coreutils"
    )

    local spec tool missing=()
    for spec in "${required_binaries[@]}"; do
        tool="${spec%%:*}"
        if ! command_exists "$tool"; then
            missing+=("$tool")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        CONFIG_VALIDATION_ERRORS+=("Missing required system utilities: ${missing[*]}")
    fi

    # Framework tools (warn only, not fatal for self-test)
    local -a framework_tools=(
        "subfinder"
        "assetfinder"
        "dnsx"
        "naabu"
        "httpx"
        "katana"
        "nuclei"
    )

    local tool missing_tools=()
    for tool in "${framework_tools[@]}"; do
        if ! command_exists "$tool"; then
            missing_tools+=("$tool")
        fi
    done

    if [[ ${#missing_tools[@]} -eq ${#framework_tools[@]} ]]; then
        CONFIG_VALIDATION_WARNINGS+=("No framework tools found (${framework_tools[*]}) - scan will not execute")
    elif [[ ${#missing_tools[@]} -gt 0 ]]; then
        CONFIG_VALIDATION_WARNINGS+=("Some framework tools missing: ${missing_tools[*]}, corresponding stages will be skipped")
    fi
}

# Validate incompatible options
config_validate_incompatible_options() {
    # Resume mode with stage selection can be problematic
    if [[ "${RESUME_MODE:-0}" -eq 1 && -n "${CLI_STAGES:-}" && "${CLI_STAGES}" != "all" ]]; then
        CONFIG_VALIDATION_WARNINGS+=("Resume mode (--resume) with stage selection (--stages) may skip required stages")
    fi

    # Resume mode with skip
    if [[ "${RESUME_MODE:-0}" -eq 1 && -n "${CLI_SKIP:-}" ]]; then
        CONFIG_VALIDATION_WARNINGS+=("Resume mode (--resume) with --skip may produce unexpected results")
    fi

    # Rate limit of 0 disables rate limiting (warn)
    if [[ "${DEFAULT_RATE_LIMIT:-150}" -eq 0 ]]; then
        CONFIG_VALIDATION_WARNINGS+=("Rate limit is 0 (disabled), may overwhelm targets")
    fi

    # Very high rate limits
    if [[ "${DEFAULT_RATE_LIMIT:-150}" -gt 1000 ]]; then
        CONFIG_VALIDATION_WARNINGS+=("Global rate limit (${DEFAULT_RATE_LIMIT}) is very high, may overwhelm targets")
    fi

    # Very low timeouts
    if [[ "${STAGE_TIMEOUT:-300}" -gt 0 && "${STAGE_TIMEOUT:-300}" -lt 30 ]]; then
        CONFIG_VALIDATION_WARNINGS+=("Stage timeout (${STAGE_TIMEOUT}s) is very low, stages may timeout frequently")
    fi
}

# Print validation summary
config_validation_summary() {
    if [[ ${#CONFIG_VALIDATION_ERRORS[@]} -gt 0 ]]; then
        log_error "Configuration validation failed with ${#CONFIG_VALIDATION_ERRORS[@]} error(s)"
        return 1
    fi

    if [[ ${#CONFIG_VALIDATION_WARNINGS[@]} -gt 0 ]]; then
        log_warn "Configuration validation passed with ${#CONFIG_VALIDATION_WARNINGS[@]} warning(s)"
    else
        log_success "Configuration validation passed"
    fi
    return 0
}