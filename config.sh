#!/usr/bin/env bash

# ============================================
# Recon Framework - Configuration
# ============================================
# shellcheck disable=SC2034


# Base directories
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-$BASE_DIR/output}"

# Colors (enabled if stdout is a terminal or if forced)
if [[ -t 1 || "${FORCE_COLOR:-0}" == "1" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    RESET='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    RESET=''
fi

# Framework settings
FRAMEWORK_NAME="Recon Framework"
FRAMEWORK_VERSION="1.2.0"

# Scope and safety configuration
ENFORCE_STRICT_SCOPE="${ENFORCE_STRICT_SCOPE:-true}"

# Concurrency & Performance
PARALLEL_PASSIVE="${PARALLEL_PASSIVE:-true}"

# DNSX settings
DNSX_THREADS="${DNSX_THREADS:-50}"

# Naabu (Port Scanning) settings
NAABU_RATE="${NAABU_RATE:-1000}"
NAABU_PORTS="${NAABU_PORTS:-top-100}"
# Known common web ports to inspect with HTTPX from Naabu results
WEB_PORTS="${WEB_PORTS:-80,443,8000,8080,8443,8888,9000,9443,3000,5000}"

# HTTPX settings
HTTPX_THREADS="${HTTPX_THREADS:-50}"
HTTPX_TIMEOUT="${HTTPX_TIMEOUT:-10}"
HTTPX_RATE_LIMIT="${HTTPX_RATE_LIMIT:-150}"

# Katana (Crawler) settings
KATANA_CONCURRENCY="${KATANA_CONCURRENCY:-10}"
KATANA_DEPTH="${KATANA_DEPTH:-2}"
KATANA_TIMEOUT="${KATANA_TIMEOUT:-10}"

# Nuclei settings (Safe defaults to prevent target denial of service)
NUCLEI_CONCURRENCY="${NUCLEI_CONCURRENCY:-25}"
NUCLEI_RATE_LIMIT="${NUCLEI_RATE_LIMIT:-150}"
NUCLEI_TIMEOUT="${NUCLEI_TIMEOUT:-10}"
NUCLEI_SEVERITY="${NUCLEI_SEVERITY:-info,low,medium,high,critical}"
NUCLEI_TAGS="${NUCLEI_TAGS:-cve,misconfig,exposure,vulnerability}"