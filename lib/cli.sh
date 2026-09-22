#!/usr/bin/env bash

# ============================================
# Recon Framework - CLI & Argument Parser
# ============================================

CLI_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v log_error >/dev/null 2>&1; then
    # shellcheck source=./logger.sh
    source "$CLI_LIB_DIR/logger.sh"
fi
if ! command -v normalize_domain >/dev/null 2>&1; then
    # shellcheck source=./validation.sh
    source "$CLI_LIB_DIR/validation.sh"
fi

# Run pre-flight environment validation
run_self_test() {
    print_banner
    separator
    log_info "Running self-test (environment validation)..."
    separator

    local checks_passed=0
    local checks_failed=0

    # 1. Bash version check
    if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
        log_success "Bash version: ${BASH_VERSION} (v4+ required)"
        checks_passed=$((checks_passed + 1))
    else
        log_error "Bash version ${BASH_VERSION} is too old (v4+ required)"
        checks_failed=$((checks_failed + 1))
    fi

    # 2. Required directories
    local base_dir="${BASE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
    if [[ -d "$base_dir" && -r "$base_dir" ]]; then
        log_success "Framework directory accessible: $base_dir"
        checks_passed=$((checks_passed + 1))
    else
        log_error "Framework directory not accessible: $base_dir"
        checks_failed=$((checks_failed + 1))
    fi

    # 3. Required libraries
    local lib_dir="${base_dir}/lib"
    if [[ -d "$lib_dir" ]]; then
        local lib_count
        lib_count=$(find "$lib_dir" -name '*.sh' -type f 2>/dev/null | wc -l)
        if (( lib_count >= 10 )); then
            log_success "Library files loaded: $(printf '%s' "$lib_count")"
            checks_passed=$((checks_passed + 1))
        else
            log_error "Insufficient library files: $(printf '%s' "$lib_count") found (expected >= 10)"
            checks_failed=$((checks_failed + 1))
        fi
    else
        log_error "Library directory not found: $lib_dir"
        checks_failed=$((checks_failed + 1))
    fi

    # 4. Configuration
    if [[ -f "${base_dir}/config.sh" && -f "${base_dir}/VERSION" ]]; then
        log_success "Configuration and VERSION files present"
        checks_passed=$((checks_passed + 1))
    else
        log_error "Missing config.sh or VERSION file"
        checks_failed=$((checks_failed + 1))
    fi

    # 5. Output directory
    local test_output_dir="${OUTPUT_DIR:-${base_dir}/output}"
    if create_directory "$test_output_dir" 2>/dev/null; then
        if [[ -w "$test_output_dir" ]]; then
            log_success "Output directory writable: $test_output_dir"
            checks_passed=$((checks_passed + 1))
        else
            log_error "Output directory not writable: $test_output_dir"
            checks_failed=$((checks_failed + 1))
        fi
    else
        log_error "Failed to create/access output directory: $test_output_dir"
        checks_failed=$((checks_failed + 1))
    fi

    # 6. Temporary directory
    local test_tmp
    test_tmp="$(mktemp -d 2>/dev/null || printf '%s/tmp_test_%s' "${TMPDIR:-/tmp}" "$$" 2>/dev/null)"
    if [[ -n "$test_tmp" && ( -d "$test_tmp" || -w "${TMPDIR:-/tmp}" ) ]]; then
        if [[ -d "$test_tmp" ]]; then rm -rf "$test_tmp"; fi
        log_success "Temporary directory available (${TMPDIR:-/tmp})"
        checks_passed=$((checks_passed + 1))
    else
        log_error "Temporary directory unavailable"
        checks_failed=$((checks_failed + 1))
    fi

    # 7. Disk space check (at least 100MB free in OUTPUT_DIR parent)
    local disk_check_dir
    disk_check_dir="$(dirname "$test_output_dir")"
    if command_exists df 2>/dev/null; then
        local avail_kb
        avail_kb=$(df -k "$disk_check_dir" 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
        if [[ "$avail_kb" =~ ^[0-9]+$ ]] && (( avail_kb >= 102400 )); then
            log_success "Disk space available: $(awk 'BEGIN{printf "%.1f", "'"$avail_kb"'"/1024}') MB free"
            checks_passed=$((checks_passed + 1))
        else
            log_warn "Low disk space: $(awk 'BEGIN{printf "%.1f", "'"$avail_kb"'"/1024}') MB free in ${disk_check_dir}"
            checks_passed=$((checks_passed + 1))
        fi
    else
        log_warn "df command not available, skipping disk space check"
    fi

    # 8. Required tool binaries
    local -a required_tools=(
        "bash:bash"
        "mkdir:coreutils"
        "awk:gawk"
        "sed:sed"
        "grep:grep"
    )
    local tool_ok=1
    local missing_tools=()
    for spec in "${required_tools[@]}"; do
        local tool="${spec%%:*}"
        if ! command_exists "$tool"; then
            missing_tools+=("$tool")
            tool_ok=0
        fi
    done
    if (( tool_ok == 1 )); then
        log_success "Core system utilities available (bash, mkdir, awk, sed, grep)"
        checks_passed=$((checks_passed + 1))
    else
        log_error "Missing system utilities: ${missing_tools[*]}"
        checks_failed=$((checks_failed + 1))
    fi

    # 9. Framework tools (optional but needed for scanning)
    local -a framework_tools=(
        subfinder
        assetfinder
        dnsx
        naabu
        httpx
        katana
        nuclei
    )
    local framework_found=()
    local framework_missing=()
    for tool in "${framework_tools[@]}"; do
        if command_exists "$tool"; then
            framework_found+=("$tool")
        else
            framework_missing+=("$tool")
        fi
    done
    if (( ${#framework_missing[@]} == 0 )); then
        log_success "All framework tools installed (${framework_tools[*]})"
        checks_passed=$((checks_passed + 1))
    elif (( ${#framework_found[@]} > 0 )); then
        log_warn "Some framework tools missing (non-fatal for self-test): ${framework_missing[*]}"
        log_info "Installed: ${framework_found[*]}"
        log_info "Missing: ${framework_missing[*]}"
        checks_passed=$((checks_passed + 1))
    else
        log_error "No framework tools installed: ${framework_missing[*]}"
        checks_failed=$((checks_failed + 1))
    fi

    # 10. Configuration values
    local config_issues=0
    if [[ ! "$STAGE_TIMEOUT" =~ ^[0-9]+$ ]] || (( STAGE_TIMEOUT < 0 )); then
        log_error "Invalid STAGE_TIMEOUT: $STAGE_TIMEOUT"
        config_issues=$((config_issues + 1))
    fi
    if [[ ! "$STAGE_RETRIES" =~ ^[0-9]+$ ]]; then
        log_error "Invalid STAGE_RETRIES: $STAGE_RETRIES"
        config_issues=$((config_issues + 1))
    fi
    if [[ "$ENFORCE_STRICT_SCOPE" != "true" && "$ENFORCE_STRICT_SCOPE" != "false" ]]; then
        log_error "Invalid ENFORCE_STRICT_SCOPE: $ENFORCE_STRICT_SCOPE"
        config_issues=$((config_issues + 1))
    fi
    if (( config_issues == 0 )); then
        log_success "Configuration values valid (timeout=$STAGE_TIMEOUT, retries=$STAGE_RETRIES)"
        checks_passed=$((checks_passed + 1))
    else
        log_error "Configuration validation failed ($config_issues issue(s))"
        checks_failed=$((checks_failed + 1))
    fi

    # Summary
    separator
    if (( checks_failed == 0 )); then
        log_success "Self-test passed: $checks_passed checks OK, $checks_failed failed"
        separator
        return 0
    else
        log_error "Self-test failed: $checks_passed checks OK, $checks_failed failed"
        separator
        return 1
    fi
}

print_banner() {
    echo -e "${CYAN}"
    cat << EOF

██████╗ ███████╗ ██████╗ ██████╗ ███╗   ██╗
██╔══██╗██╔════╝██╔════╝██╔═══██╗████╗  ██║
██████╔╝█████╗  ██║     ██║   ██║██╔██╗ ██║
██╔══██╗██╔══╝  ██║     ██║   ██║██║╚██╗██║
██║  ██║███████╗╚██████╗╚██████╔╝██║ ╚████║
╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═══╝

        ${FRAMEWORK_NAME:-Recon Framework} v${FRAMEWORK_VERSION}

EOF
    echo -e "${RESET}"
}

usage() {
    cat << EOF

Usage:
  ./recon.sh -d <domain.com> [options]
  ./recon.sh -d <domain1,domain2,...> [options]
  ./recon.sh -l <targets.txt> [options]

Core Options:
  -d, --domain <domain(s)>    Target domain(s), single or comma-separated (required unless -l)
  -l, --list <file>           File containing target domains (one per line)
  -o, --output <directory>    Custom output workspace directory
  -r, --resume                Resume mode (skip stages with existing valid output)
  -v, --verbose               Enable verbose console debugging output
  -h, --help                  Display this help message
  --self-test                 Run environment validation (no target required)

Pipeline Orchestration:
  --stages <s1,s2,...>        Comma-separated stages to run (default: all)
                              Available: subdomains, dns, ports, live, crawling, vuln, reports
  --skip <s1,s2,...>          Comma-separated stages to skip

Execution Control:
  -t, --threads <n>           Concurrency threads for tools (default: 50)
  --rate-limit <n>            Maximum requests per second (default: 150)
  --timeout <seconds>         Stage execution timeout (default: 300)
  --retries <count>           Max retry attempts on stage failure (default: 1)

Security Notice:
  This tool is intended strictly for authorized security assessments,
  penetration testing, and bug bounty programs where explicit written
  authorization has been granted. The operator assumes full responsibility
  for ensuring all scans remain strictly in-scope.

Examples:
  ./recon.sh -d example.com
  ./recon.sh -d example.com,target.org -t 25 --rate-limit 100
  ./recon.sh -l targets.txt -o /custom/output
  ./recon.sh -d example.com --stages subdomains,dns,live
  ./recon.sh -d example.com --skip nuclei,ports
  ./recon.sh -d example.com -r --verbose

EOF
}

# shellcheck disable=SC2034
parse_cli_args() {
    local custom_out=""
    local cli_threads=""
    local cli_rate=""
    local cli_to=""
    local cli_ret=""
    local -a raw_targets=()
    local -a target_files=()

    TARGET_DOMAINS=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--domain)
                [[ $# -ge 2 ]] || { log_error "Option '$1' requires an argument."; exit 1; }
                raw_targets+=("$2")
                shift 2
                ;;
            -l|--list)
                [[ $# -ge 2 ]] || { log_error "Option '$1' requires an argument."; exit 1; }
                target_files+=("$2")
                shift 2
                ;;
            -o|--output)
                [[ $# -ge 2 ]] || { log_error "Option '$1' requires an argument."; exit 1; }
                custom_out="$2"
                shift 2
                ;;
            -t|--threads)
                [[ $# -ge 2 ]] || { log_error "Option '$1' requires an argument."; exit 1; }
                cli_threads="$2"
                shift 2
                ;;
            --rate-limit)
                [[ $# -ge 2 ]] || { log_error "Option '$1' requires an argument."; exit 1; }
                cli_rate="$2"
                shift 2
                ;;
            --timeout)
                [[ $# -ge 2 ]] || { log_error "Option '$1' requires an argument."; exit 1; }
                cli_to="$2"
                shift 2
                ;;
            --retries)
                [[ $# -ge 2 ]] || { log_error "Option '$1' requires an argument."; exit 1; }
                cli_ret="$2"
                shift 2
                ;;
            --stages)
                [[ $# -ge 2 ]] || { log_error "Option '$1' requires an argument."; exit 1; }
                CLI_STAGES="$2"
                shift 2
                ;;
            --skip)
                [[ $# -ge 2 ]] || { log_error "Option '$1' requires an argument."; exit 1; }
                CLI_SKIP="$2"
                shift 2
                ;;
            -r|--resume)
                RESUME_MODE=1
                shift
                ;;
            -v|--verbose)
                VERBOSE=1
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            --self-test)
                SELF_TEST=1
                shift
                ;;
            *)
                log_error "Unknown option or argument: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Apply CLI Overrides with validation
    if [[ -n "$custom_out" ]]; then
        OUTPUT_DIR="$custom_out"
    fi
    if [[ -n "$cli_threads" ]]; then
        if [[ ! "$cli_threads" =~ ^[0-9]+$ ]] || (( cli_threads <= 0 )); then
            log_error "Invalid threads value: '$cli_threads' (must be a positive integer)."
            exit 1
        fi
        DNSX_THREADS="$cli_threads"
        HTTPX_THREADS="$cli_threads"
        KATANA_CONCURRENCY="$cli_threads"
        NUCLEI_CONCURRENCY="$cli_threads"
    fi
    if [[ -n "$cli_rate" ]]; then
        if [[ ! "$cli_rate" =~ ^[0-9]+$ ]] || (( cli_rate <= 0 )); then
            log_error "Invalid rate-limit value: '$cli_rate' (must be a positive integer)."
            exit 1
        fi
        HTTPX_RATE_LIMIT="$cli_rate"
        NAABU_RATE="$cli_rate"
        NUCLEI_RATE_LIMIT="$cli_rate"
    fi
    if [[ -n "$cli_to" ]]; then
        if [[ ! "$cli_to" =~ ^[0-9]+$ ]] || (( cli_to < 0 )); then
            log_error "Invalid timeout value: '$cli_to' (must be a non-negative integer)."
            exit 1
        fi
        STAGE_TIMEOUT="$cli_to"
    fi
    if [[ -n "$cli_ret" ]]; then
        if [[ ! "$cli_ret" =~ ^[0-9]+$ ]] || (( cli_ret < 0 )); then
            log_error "Invalid retries value: '$cli_ret' (must be a non-negative integer)."
            exit 1
        fi
        STAGE_RETRIES="$cli_ret"
    fi

    # Ingest target list files
    local f
    for f in "${target_files[@]}"; do
        if [[ ! -f "$f" ]]; then
            log_error "Target list file not found: $f"
            exit 1
        fi
        if [[ ! -r "$f" ]]; then
            log_error "Target list file is not readable: $f"
            exit 1
        fi
        while IFS= read -r line || [[ -n "$line" ]]; do
            local trimmed="${line#"${line%%[![:space:]]*}"}"
            trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
            if [[ -n "$trimmed" && "$trimmed" != \#* ]]; then
                raw_targets+=("$trimmed")
            fi
        done < "$f"
    done

    # Validate that at least one target domain was supplied
    # (unless --self-test was requested, which needs no target)
    if [[ "${SELF_TEST:-0}" -ne 1 ]] && (( ${#raw_targets[@]} == 0 )); then
        print_banner
        log_error "No target domain supplied."
        usage
        exit 1
    fi

    # Normalize, validate, and deduplicate targets
    declare -A seen_targets=()
    local raw_entry
    for raw_entry in "${raw_targets[@]}"; do
        local IFS=','
        local -a split_entries
        read -r -a split_entries <<< "$raw_entry"
        local item
        for item in "${split_entries[@]}"; do
            local norm
            norm="$(normalize_domain "$item")"
            if [[ -z "$norm" ]]; then
                continue
            fi
            if ! validate_domain "$norm"; then
                exit 1
            fi
            if [[ -z "${seen_targets[$norm]:-}" ]]; then
                seen_targets["$norm"]=1
                TARGET_DOMAINS+=("$norm")
            fi
        done
    done

    if (( ${#TARGET_DOMAINS[@]} == 0 )) && [[ "${SELF_TEST:-0}" -ne 1 ]]; then
        log_error "No valid target domain supplied."
        exit 1
    fi

    # Backward compatibility for single target variable
    if (( ${#TARGET_DOMAINS[@]} > 0 )); then
        DOMAIN="${TARGET_DOMAINS[0]}"
    fi
    export DOMAIN TARGET_DOMAINS

    return 0
}
