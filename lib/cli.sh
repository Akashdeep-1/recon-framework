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

        ${FRAMEWORK_NAME:-Recon Framework} v${FRAMEWORK_VERSION:-1.2.0}

EOF
    echo -e "${RESET}"
}

usage() {
    cat << EOF

Usage:
  ./recon.sh -d <domain.com> [options]

Core Options:
  -d, --domain <domain>       Target Domain (required)
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
  ./recon.sh -d example.com -o /custom/output -t 25 --rate-limit 100
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

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--domain)
                [[ $# -ge 2 ]] || { log_error "Option '$1' requires an argument."; exit 1; }
                DOMAIN="$2"
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

    # Apply CLI Overrides
    if [[ -n "$custom_out" ]]; then
        OUTPUT_DIR="$custom_out"
    fi
    if [[ -n "$cli_threads" ]]; then
        DNSX_THREADS="$cli_threads"
        HTTPX_THREADS="$cli_threads"
        KATANA_CONCURRENCY="$cli_threads"
        NUCLEI_CONCURRENCY="$cli_threads"
    fi
    if [[ -n "$cli_rate" ]]; then
        HTTPX_RATE_LIMIT="$cli_rate"
        NAABU_RATE="$cli_rate"
        NUCLEI_RATE_LIMIT="$cli_rate"
    fi
    if [[ -n "$cli_to" ]]; then
        STAGE_TIMEOUT="$cli_to"
    fi
    if [[ -n "$cli_ret" ]]; then
        STAGE_RETRIES="$cli_ret"
    fi

    # Validate target domain
    if [[ -z "${DOMAIN:-}" ]]; then
        print_banner
        log_error "No target domain supplied."
        usage
        exit 1
    fi

    DOMAIN="$(normalize_domain "$DOMAIN")"
    if ! validate_domain "$DOMAIN"; then
        exit 1
    fi

    return 0
}
