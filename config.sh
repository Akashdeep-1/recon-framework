#!/usr/bin/env bash

# ============================================
# Recon Framework - Configuration
# ============================================

# Base directories
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$BASE_DIR/output"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RESET='\033[0m'

# Framework settings
FRAMEWORK_NAME="Recon Framework"
FRAMEWORK_VERSION="1.2.0"