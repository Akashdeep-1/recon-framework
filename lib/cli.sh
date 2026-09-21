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
    if (( ${#raw_targets[@]} == 0 )); then
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

    if (( ${#TARGET_DOMAINS[@]} == 0 )); then
        log_error "No valid target domain supplied."
        exit 1
    fi

    # Backward compatibility for single target variable
    DOMAIN="${TARGET_DOMAINS[0]}"
    export DOMAIN TARGET_DOMAINS

    return 0
}
