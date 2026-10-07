#!/usr/bin/env bash
# shellcheck disable=SC2034

# ============================================
# Recon Framework - DAG Data Model and Validation
# ============================================

DAG_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v log_error >/dev/null 2>&1; then
    # shellcheck source=./logger.sh
    source "$DAG_LIB_DIR/logger.sh"
fi

# ============================================
# Constants
# ============================================

# Canonical stage IDs in execution order
readonly DAG_STAGE_IDS=(
    "subdomains"
    "dns"
    "ports"
    "live"
    "crawling"
    "vuln"
    "reports"
)

# Valid failure policies
readonly DAG_VALID_FAILURE_POLICIES=(
    "FAIL_FAST"
    "CONTINUE"
    "SKIP_DEPENDENTS"
    "RETRY"
)

# Valid conditions
readonly DAG_VALID_CONDITIONS=(
    "true"
    "has_subdomains"
    "has_resolved_hosts"
    "has_web_targets"
    "has_live_urls"
    "has_urls"
)

# Parallel groups
readonly DAG_VALID_PARALLEL_GROUPS=(
    "passive"
    "dns_resolve"
    "port_scan"
    "http_probe"
    "crawling"
    "vuln_scan"
    "reporting"
)

# ============================================
# Stage Data Model Helpers
# ============================================

# Validate a stage ID format
dag_validate_stage_id() {
    local id="$1"
    if [[ -z "$id" ]]; then
        log_error "Stage ID cannot be empty"
        return 1
    fi
    if [[ "$id" =~ [^a-zA-Z0-9_-] ]]; then
        log_error "Stage ID contains invalid characters: $id"
        return 1
    fi
    return 0
}

# Validate failure policy
dag_validate_failure_policy() {
    local policy="$1"
    local valid=0
    for p in "${DAG_VALID_FAILURE_POLICIES[@]}"; do
        if [[ "$p" == "$policy" ]]; then
            valid=1
            break
        fi
    done
    if (( valid == 0 )); then
        log_error "Invalid failure policy: $policy (valid: ${DAG_VALID_FAILURE_POLICIES[*]})"
        return 1
    fi
    return 0
}

# Validate condition
dag_validate_condition() {
    local condition="$1"
    local valid=0
    for c in "${DAG_VALID_CONDITIONS[@]}"; do
        if [[ "$c" == "$condition" ]]; then
            valid=1
            break
        fi
    done
    if (( valid == 0 )); then
        log_error "Invalid condition: $condition (valid: ${DAG_VALID_CONDITIONS[*]})"
        return 1
    fi
    return 0
}

# Validate parallel group
dag_validate_parallel_group() {
    local group="$1"
    local valid=0
    for g in "${DAG_VALID_PARALLEL_GROUPS[@]}"; do
        if [[ "$g" == "$group" ]]; then
            valid=1
            break
        fi
    done
    if (( valid == 0 )); then
        log_error "Invalid parallel group: $group (valid: ${DAG_VALID_PARALLEL_GROUPS[*]})"
        return 1
    fi
    return 0
}

# ============================================
# Canonical DAG Definition
# ============================================

# Define the canonical seven-stage DAG
# Uses arrays to maintain deterministic ordering
dag_canonical_stages() {
    # Stage definitions (id, label, deps, inputs, outputs, cmd, condition, failure_policy, parallel_group)
    # Using indexed arrays for deterministic ordering

    DAG_STAGE_ID=(
        "subdomains"
        "dns"
        "ports"
        "live"
        "crawling"
        "vuln"
        "reports"
    )

    DAG_STAGE_LABEL=(
        "Subdomain Discovery"
        "DNS Resolution"
        "Port Discovery"
        "HTTP Probing"
        "URL Crawling"
        "Vulnerability Scan"
        "Report Generation"
    )

    DAG_STAGE_DEPS=(
        ""
        "subdomains"
        "dns"
        "dns,ports"
        "live"
        "crawling,live"
        "vuln"
    )

    DAG_STAGE_INPUTS=(
        "target_domain"
        "subdomains/all.txt"
        "dns/resolved.txt"
        "dns/resolved.txt,ports/web_candidates.txt"
        "live/urls.txt"
        "crawling/katana.txt,live/urls.txt"
        "all"
    )

    DAG_STAGE_OUTPUTS=(
        "subdomains/all.txt subdomains/hosts.jsonl"
        "dns/resolved.txt dns/resolved.jsonl"
        "ports/ports.txt ports/ports.jsonl ports/web_candidates.txt"
        "live/httpx.txt live/urls.txt"
        "crawling/katana.txt crawling/urls.jsonl"
        "vuln/findings.jsonl vuln/summary.json"
        "reports/summary.md reports/summary.html"
    )

    DAG_STAGE_CMD=(
        "execute_subdomains_stage"
        "run_dnsx"
        "run_naabu"
        "execute_live_stage"
        "run_katana"
        "run_nuclei"
        "execute_reports_stage"
    )

    DAG_STAGE_CONDITION=(
        "true"
        "has_subdomains"
        "has_resolved_hosts"
        "has_web_targets"
        "has_live_urls"
        "has_urls"
        "true"
    )

    DAG_STAGE_FAILURE_POLICY=(
        "FAIL_FAST"
        "FAIL_FAST"
        "FAIL_FAST"
        "FAIL_FAST"
        "CONTINUE"
        "CONTINUE"
        "FAIL_FAST"
    )

    DAG_STAGE_PARALLEL_GROUP=(
        "passive"
        "dns_resolve"
        "port_scan"
        "http_probe"
        "crawling"
        "vuln_scan"
        "reporting"
    )

    DAG_STAGE_TIMEOUT=(
        300
        300
        300
        300
        300
        300
        300
    )

    DAG_STAGE_RETRIES=(
        1
        1
        1
        1
        1
        1
        1
    )

    DAG_STAGE_RATE_LIMIT=(
        "subfinder"
        ""
        "naabu"
        "httpx"
        "katana"
        "nuclei"
        ""
    )
}

# ============================================
# DAG Validation
# ============================================

# Load canonical stages
dag_load_canonical() {
    dag_canonical_stages
    DAG_LOADED=1
}

# Validate all stage IDs are unique
dag_validate_unique_ids() {
    local -A seen=()
    local id
    for id in "${DAG_STAGE_ID[@]}"; do
        if [[ -n "${seen[$id]:-}" ]]; then
            log_error "Duplicate stage ID: $id"
            return 1
        fi
        seen["$id"]=1
    done
    return 0
}

# Validate all stage IDs are valid format
dag_validate_all_ids() {
    local id
    for id in "${DAG_STAGE_ID[@]}"; do
        dag_validate_stage_id "$id" || return 1
    done
    return 0
}

# Validate all failure policies
dag_validate_all_failure_policies() {
    local policy
    for policy in "${DAG_STAGE_FAILURE_POLICY[@]}"; do
        dag_validate_failure_policy "$policy" || return 1
    done
    return 0
}

# Validate all conditions
dag_validate_all_conditions() {
    local condition
    for condition in "${DAG_STAGE_CONDITION[@]}"; do
        dag_validate_condition "$condition" || return 1
    done
    return 0
}

# Validate all parallel groups
dag_validate_all_parallel_groups() {
    local group
    for group in "${DAG_STAGE_PARALLEL_GROUP[@]}"; do
        if [[ -n "$group" ]]; then
            dag_validate_parallel_group "$group" || return 1
        fi
    done
    return 0
}

# Validate dependencies reference existing stages
dag_validate_dependencies() {
    local -A stage_exists=()
    local id
    for id in "${DAG_STAGE_ID[@]}"; do
        stage_exists["$id"]=1
    done

    local i
    for (( i=0; i<${#DAG_STAGE_ID[@]}; i++ )); do
        local id="${DAG_STAGE_ID[i]}"
        local deps="${DAG_STAGE_DEPS[i]}"

        if [[ -n "$deps" ]]; then
            local IFS=','
            read -r -a dep_array <<< "$deps"
            local dep
            for dep in "${dep_array[@]}"; do
                dep="${dep// /}"
                if [[ -z "${stage_exists[$dep]:-}" ]]; then
                    log_error "Stage '$id' depends on missing stage: $dep"
                    return 1
                fi
                if [[ "$dep" == "$id" ]]; then
                    log_error "Stage '$id' has self-dependency"
                    return 1
                fi
            done
        fi
    done
    return 0
}

# Detect cycles using Kahn's algorithm (deterministic)
dag_detect_cycles() {
    if [[ "${DAG_DEBUG:-0}" == "1" ]]; then
        echo "DEBUG: dag_detect_cycles called"
    fi
    local num_stages=${#DAG_STAGE_ID[@]}
    local -A in_degree=()
    local -A adj=()

    # Initialize in-degree
    local id
    for id in "${DAG_STAGE_ID[@]}"; do
        in_degree["$id"]=0
        if [[ "${DAG_DEBUG:-0}" == "1" ]]; then
            echo "DEBUG init: $id in_degree=0"
        fi
    done

    # Build adjacency and compute in-degrees
    local i
    for (( i=0; i<num_stages; i++ )); do
        local id="${DAG_STAGE_ID[i]}"
        local deps="${DAG_STAGE_DEPS[i]}"

        if [[ -n "$deps" ]]; then
            local IFS=','
            read -r -a dep_array <<< "$deps"
            local dep
            for dep in "${dep_array[@]}"; do
                dep="${dep// /}"
                if [[ -z "${adj[$dep]:-}" ]]; then
                    adj["$dep"]="$id"
                else
                    adj["$dep"]="${adj[$dep]} $id"
                fi
                in_degree["$id"]=$(( in_degree["$id"] + 1 ))
                if [[ "${DAG_DEBUG:-0}" == "1" ]]; then
                    echo "DEBUG edge: $dep -> $id (in_degree of $id now ${in_degree[$id]})"
                fi
            done
        else
            if [[ "${DAG_DEBUG:-0}" == "1" ]]; then
                echo "DEBUG: $id has no deps"
            fi
        fi
    done

    # DEBUG: Print adjacency and in-degrees
    if [[ "${DAG_DEBUG:-0}" == "1" ]]; then
        for id in "${DAG_STAGE_ID[@]}"; do
            echo "DEBUG final: $id - in_degree=${in_degree[$id]:-0}, adj=${adj[$id]:-none}" >&2
        done
    fi

    # Kahn's algorithm - deterministic by using stage order
        local queue=()
        for id in "${DAG_STAGE_ID[@]}"; do
            if (( in_degree["$id"] == 0 )); then
                queue+=("$id")
            fi
        done

        if [[ "${DAG_DEBUG:-0}" == "1" ]]; then
            echo "DEBUG: Initial queue: ${queue[*]}" >&2
        fi

        local topo_order=()
        while (( ${#queue[@]} > 0 )); do
            # Pop first (deterministic FIFO)
            local current="${queue[0]}"
            queue=("${queue[@]:1}")
            topo_order+=("$current")

            if [[ "${DAG_DEBUG:-0}" == "1" ]]; then
                echo "DEBUG: Processing $current, topo_order now: ${topo_order[*]}" >&2
            fi

            # Process neighbors
        local neighbors="${adj[$current]:-}"
        if [[ "${DAG_DEBUG:-0}" == "1" ]]; then
            echo "DEBUG: $current neighbors: '$neighbors'" >&2
        fi
        local old_ifs="$IFS"
        IFS=' '
        for neighbor in $neighbors; do
            IFS="$old_ifs"
            if [[ "${DAG_DEBUG:-0}" == "1" ]]; then
                echo "DEBUG: Processing neighbor '$neighbor', in_degree before: ${in_degree[$neighbor]}" >&2
            fi
            in_degree["$neighbor"]=$(( in_degree["$neighbor"] - 1 ))
            if [[ "${DAG_DEBUG:-0}" == "1" ]]; then
                echo "DEBUG: $neighbor in_degree after decrement: ${in_degree[$neighbor]}" >&2
            fi
            if (( in_degree["$neighbor"] == 0 )); then
                queue+=("$neighbor")
                if [[ "${DAG_DEBUG:-0}" == "1" ]]; then
                    echo "DEBUG: $neighbor in_degree now 0, added to queue" >&2
                fi
            fi
        done
        IFS="$old_ifs"
        done

        if (( ${#topo_order[@]} != num_stages )); then
        log_error "Cycle detected in DAG (topological sort incomplete: ${#topo_order[@]}/${num_stages} stages)"
        return 1
    fi

    # Store topological order for deterministic execution
    DAG_TOPO_ORDER=("${topo_order[@]}")
    return 0
}

# Validate all inputs/outputs are declared
dag_validate_io() {
    local i
    for (( i=0; i<${#DAG_STAGE_ID[@]}; i++ )); do
        local inputs="${DAG_STAGE_INPUTS[i]}"
        local outputs="${DAG_STAGE_OUTPUTS[i]}"

        if [[ -z "$inputs" ]]; then
            log_error "Stage '${DAG_STAGE_ID[i]}' has no inputs declared"
            return 1
        fi
        if [[ -z "$outputs" ]]; then
            log_error "Stage '${DAG_STAGE_ID[i]}' has no outputs declared"
            return 1
        fi
    done
    return 0
}

# Validate all commands exist as functions
dag_validate_commands() {
    local i
    for (( i=0; i<${#DAG_STAGE_ID[@]}; i++ )); do
        local cmd="${DAG_STAGE_CMD[i]}"
        if ! declare -f "$cmd" >/dev/null 2>&1; then
            log_error "Stage '${DAG_STAGE_ID[i]}' references undefined command: $cmd"
            return 1
        fi
    done
    return 0
}

# Full DAG validation
dag_validate_all() {
    DAG_ERRORS=()

    # Only load canonical if not already loaded with a custom DAG
    if [[ "${DAG_LOADED:-0}" -ne 1 ]]; then
        dag_load_canonical || return 1
    fi

    dag_validate_all_ids || return 1
    dag_validate_unique_ids || return 1
    dag_validate_all_failure_policies || return 1
    dag_validate_all_conditions || return 1
    dag_validate_all_parallel_groups || return 1
    dag_validate_dependencies || return 1
    dag_detect_cycles || return 1
    dag_validate_io || return 1
    dag_validate_commands || return 1

    return 0
}

# Get topological order
dag_get_topo_order() {
    if [[ -z "${DAG_TOPO_ORDER:-}" ]]; then
        dag_detect_cycles >/dev/null || return 1
    fi
    printf '%s\n' "${DAG_TOPO_ORDER[@]}"
}

# Get stage index by ID
dag_get_stage_index() {
    local target_id="$1"
    local i
    for (( i=0; i<${#DAG_STAGE_ID[@]}; i++ )); do
        if [[ "${DAG_STAGE_ID[i]}" == "$target_id" ]]; then
            echo "$i"
            return 0
        fi
    done
    return 1
}

# Get stage dependencies
dag_get_stage_deps() {
    local index
    index=$(dag_get_stage_index "$1") || return 1
    echo "${DAG_STAGE_DEPS[index]:-}"
}

# Get stage condition
dag_get_stage_condition() {
    local index
    index=$(dag_get_stage_index "$1") || return 1
    echo "${DAG_STAGE_CONDITION[index]:-}"
}

# Get stage failure policy
dag_get_stage_failure_policy() {
    local index
    index=$(dag_get_stage_index "$1") || return 1
    echo "${DAG_STAGE_FAILURE_POLICY[index]:-FAIL_FAST}"
}

# Get stage parallel group
dag_get_stage_parallel_group() {
    local index
    index=$(dag_get_stage_index "$1") || return 1
    echo "${DAG_STAGE_PARALLEL_GROUP[index]:-}"
}

# Get stage command
dag_get_stage_cmd() {
    local index
    index=$(dag_get_stage_index "$1") || return 1
    echo "${DAG_STAGE_CMD[index]:-}"
}

# Get stage label
dag_get_stage_label() {
    local index
    index=$(dag_get_stage_index "$1") || return 1
    echo "${DAG_STAGE_LABEL[index]:-}"
}

# Get stage inputs
dag_get_stage_inputs() {
    local index
    index=$(dag_get_stage_index "$1") || return 1
    echo "${DAG_STAGE_INPUTS[index]:-}"
}

# Get stage outputs
dag_get_stage_outputs() {
    local index
    index=$(dag_get_stage_index "$1") || return 1
    echo "${DAG_STAGE_OUTPUTS[index]:-}"
}

# Get stage timeout
dag_get_stage_timeout() {
    local index
    index=$(dag_get_stage_index "$1") || return 1
    echo "${DAG_STAGE_TIMEOUT[index]:-0}"
}

# Get stage retries
dag_get_stage_retries() {
    local index
    index=$(dag_get_stage_index "$1") || return 1
    echo "${DAG_STAGE_RETRIES[index]:-0}"
}

# Get stage rate limit
dag_get_stage_rate_limit() {
    local index
    index=$(dag_get_stage_index "$1") || return 1
    echo "${DAG_STAGE_RATE_LIMIT[index]:-}"
}

# ============================================
# Condition Evaluation Helpers
# ============================================

# has_subdomains - check if subdomains stage has output
dag_condition_has_subdomains() {
    local workspace="$1"
    [[ -s "${workspace}/subdomains/all.txt" ]]
}

# has_resolved_hosts
dag_condition_has_resolved_hosts() {
    local workspace="$1"
    [[ -s "${workspace}/dns/resolved.txt" ]]
}

# has_web_targets
dag_condition_has_web_targets() {
    local workspace="$1"
    [[ -s "${workspace}/ports/web_candidates.txt" ]] || [[ -s "${workspace}/dns/resolved.txt" ]]
}

# has_live_urls
dag_condition_has_live_urls() {
    local workspace="$1"
    [[ -s "${workspace}/live/urls.txt" ]]
}

# has_urls
dag_condition_has_urls() {
    local workspace="$1"
    [[ -s "${workspace}/crawling/katana.txt" ]] || [[ -s "${workspace}/live/urls.txt" ]]
}

# Evaluate condition by name
dag_evaluate_condition() {
    local condition="$1"
    local workspace="$2"

    case "$condition" in
        true)
            return 0
            ;;
        has_subdomains)
            dag_condition_has_subdomains "$workspace"
            ;;
        has_resolved_hosts)
            dag_condition_has_resolved_hosts "$workspace"
            ;;
        has_web_targets)
            dag_condition_has_web_targets "$workspace"
            ;;
        has_live_urls)
            dag_condition_has_live_urls "$workspace"
            ;;
        has_urls)
            dag_condition_has_urls "$workspace"
            ;;
        *)
            log_error "Unknown condition: $condition"
            return 1
            ;;
    esac
}

# ============================================
# Manifest Compatibility
# ============================================

# Check if manifest has DAG metadata
dag_manifest_has_dag_metadata() {
    local manifest_file="$1"
    if [[ ! -f "$manifest_file" ]]; then
        return 1
    fi
    local dag_version
    # Use pure bash to extract dag_version (avoids path issues with Windows Python)
    dag_version=$(grep -o '"dag_version"[[:space:]]*:[[:space:]]*[0-9]*' "$manifest_file" 2>/dev/null | sed 's/.*://' | tr -d ' ' || echo 0)
    (( dag_version >= 1 ))
}

# Get DAG version from manifest
dag_manifest_get_version() {
    local manifest_file="$1"
    grep -o '"dag_version"[[:space:]]*:[[:space:]]*[0-9]*' "$manifest_file" 2>/dev/null | sed 's/.*://' | tr -d ' ' || echo 0
}

# ============================================
# Exported Variables
# ============================================

export DAG_STAGE_ID
export DAG_STAGE_LABEL
export DAG_STAGE_DEPS
export DAG_STAGE_INPUTS
export DAG_STAGE_OUTPUTS
export DAG_STAGE_CMD
export DAG_STAGE_CONDITION
export DAG_STAGE_FAILURE_POLICY
export DAG_STAGE_PARALLEL_GROUP
export DAG_STAGE_TIMEOUT
export DAG_STAGE_RETRIES
export DAG_STAGE_RATE_LIMIT
export DAG_TOPO_ORDER

# Load canonical on source
dag_load_canonical