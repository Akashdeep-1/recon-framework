#!/usr/bin/env bash

# ============================================
# Recon Framework - DAG Executor Core
# ============================================

DAG_EXEC_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v log_error >/dev/null 2>&1; then
    # shellcheck source=./logger.sh
    source "$DAG_EXEC_LIB_DIR/logger.sh"
fi
if ! command -v create_workspace >/dev/null 2>&1; then
    # shellcheck source=./filesystem.sh
    source "$DAG_EXEC_LIB_DIR/filesystem.sh"
fi
if ! command -v dag_load_canonical >/dev/null 2>&1; then
    # shellcheck source=./dag.sh
    source "$DAG_EXEC_LIB_DIR/dag.sh"
fi
if ! command -v run_pipeline_stage >/dev/null 2>&1; then
    # shellcheck source=./orchestration.sh
    source "$DAG_EXEC_LIB_DIR/orchestration.sh"
fi
if ! command -v update_stage_manifest >/dev/null 2>&1; then
    # shellcheck source=./manifest.sh
    source "$DAG_EXEC_LIB_DIR/manifest.sh"
fi
if ! command -v generate_reports >/dev/null 2>&1; then
    # shellcheck source=./report.sh
    source "$DAG_EXEC_LIB_DIR/report.sh"
fi

# ============================================
# Stage State Constants
# ============================================
readonly DAG_STATE_PENDING="PENDING"
readonly DAG_STATE_READY="READY"
readonly DAG_STATE_RUNNING="RUNNING"
readonly DAG_STATE_SUCCESS="SUCCESS"
readonly DAG_STATE_FAILED="FAILED"
readonly DAG_STATE_BLOCKED="BLOCKED"
readonly DAG_STATE_SKIPPED="SKIPPED"

# ============================================
# DAG Executor State (internal)
# ============================================
DAG_EXEC_STAGE_STATES=()
DAG_EXEC_WORKSPACE=""

# ============================================
# Initialize executor with validated DAG
# ============================================
dag_exec_init() {
    local workspace="$1"

    DAG_EXEC_WORKSPACE="$workspace"

    # Ensure workspace directory structure exists
    local directories=(
        "$workspace/subdomains"
        "$workspace/dns"
        "$workspace/live"
        "$workspace/ports"
        "$workspace/urls"
        "$workspace/nuclei"
        "$workspace/reports"
        "$workspace/logs"
    )
    for directory in "${directories[@]}"; do
        mkdir -p "$directory"
    done

    # Load canonical DAG only if not already loaded (test DAGs set their own)
    if [[ -z "${DAG_LOADED:-}" || ${#DAG_STAGE_ID[@]} -eq 0 ]]; then
        dag_load_canonical
    fi

    # Validate DAG before execution
    if ! dag_validate_all; then
        log_error "DAG validation failed before execution"
        return 1
    fi

    # Initialize all stages to PENDING
    local i
    for (( i=0; i<${#DAG_STAGE_ID[@]}; i++ )); do
        DAG_EXEC_STAGE_STATES[i]="$DAG_STATE_PENDING"
    done

    log_debug "DAG executor initialized with ${#DAG_STAGE_ID[@]} stages"
    return 0
}

# ============================================
# Get current state of a stage
# ============================================
dag_exec_get_state() {
    local stage_id="$1"
    local index
    index=$(dag_get_stage_index "$stage_id") || return 1
    echo "${DAG_EXEC_STAGE_STATES[index]}"
}

# ============================================
# Set state of a stage
# ============================================
dag_exec_set_state() {
    local stage_id="$1"
    local new_state="$2"
    local index
    index=$(dag_get_stage_index "$stage_id") || return 1
    DAG_EXEC_STAGE_STATES[index]="$new_state"
    log_debug "Stage '$stage_id' state: $new_state"
}

# ============================================
# Check if all dependencies of a stage are satisfied (SUCCESS or SKIPPED)
# ============================================
dag_exec_deps_satisfied() {
    local stage_id="$1"
    local deps
    deps=$(dag_get_stage_deps "$stage_id") || return 1

    if [[ -z "$deps" ]]; then
        return 0  # No dependencies
    fi

    local IFS=','
    read -r -a dep_array <<< "$deps"
    local dep
    for dep in "${dep_array[@]}"; do
        dep="${dep// /}"
        local dep_state
        dep_state=$(dag_exec_get_state "$dep")
        # Dependencies must be SUCCESS or SKIPPED (not PENDING, RUNNING, FAILED, BLOCKED)
        if [[ "$dep_state" != "$DAG_STATE_SUCCESS" && "$dep_state" != "$DAG_STATE_SKIPPED" ]]; then
            return 1
        fi
    done

    return 0
}

# ============================================
# Check if a stage has any failed dependencies
# ============================================
dag_exec_has_failed_deps() {
    local stage_id="$1"
    local deps
    deps=$(dag_get_stage_deps "$stage_id") || return 1

    if [[ -z "$deps" ]]; then
        return 1  # No dependencies = no failed deps
    fi

    local IFS=','
    read -r -a dep_array <<< "$deps"
    local dep
    for dep in "${dep_array[@]}"; do
        dep="${dep// /}"
        local dep_state
        dep_state=$(dag_exec_get_state "$dep")
        if [[ "$dep_state" == "$DAG_STATE_FAILED" ]]; then
            return 0
        fi
    done

    return 1
}

# ============================================
# Check if a stage has any skipped dependencies (to propagate SKIPPED)
# ============================================
dag_exec_has_skipped_deps() {
    local stage_id="$1"
    local deps
    deps=$(dag_get_stage_deps "$stage_id") || return 1

    if [[ -z "$deps" ]]; then
        return 1
    fi

    local IFS=','
    read -r -a dep_array <<< "$deps"
    local dep
    for dep in "${dep_array[@]}"; do
        dep="${dep// /}"
        local dep_state
        dep_state=$(dag_exec_get_state "$dep")
        if [[ "$dep_state" == "$DAG_STATE_SKIPPED" ]]; then
            return 0
        fi
    done

    return 1
}

# ============================================
# Check if a stage should be blocked due to dependency failure
# ============================================
dag_exec_should_block() {
    local stage_id="$1"

    # Check if any dependency failed - if so, this stage cannot run
    local deps
    deps=$(dag_get_stage_deps "$stage_id") || return 1

    if [[ -z "$deps" ]]; then
        return 1  # No dependencies = cannot be blocked
    fi

    local IFS=','
    read -r -a dep_array <<< "$deps"
    local dep
    for dep in "${dep_array[@]}"; do
        dep="${dep// /}"
        local dep_state
        dep_state=$(dag_exec_get_state "$dep")
        if [[ "$dep_state" == "$DAG_STATE_FAILED" ]]; then
            return 0  # Block this stage because dependency failed
        fi
    done

    return 1
}

# ============================================
# Find all stages that are ready to execute
# ============================================
dag_exec_get_ready_stages() {
    local ready_stages=()
    local i
    for (( i=0; i<${#DAG_STAGE_ID[@]}; i++ )); do
        local stage_id="${DAG_STAGE_ID[i]}"
        local stage_state="${DAG_EXEC_STAGE_STATES[i]}"

        if [[ "$stage_state" != "$DAG_STATE_PENDING" ]]; then
            continue
        fi

        # Check if any dependency has failed - if so, block this stage
        if dag_exec_has_failed_deps "$stage_id"; then
            dag_exec_set_state "$stage_id" "$DAG_STATE_BLOCKED"
            log_info "Stage '$stage_id' blocked due to failed dependency"
            jsonl_stage_blocked "$stage_id" "dependency_failed"
            continue
        fi

        # Check if any dependency was skipped - if so, skip this stage too
        if dag_exec_has_skipped_deps "$stage_id"; then
            dag_exec_set_state "$stage_id" "$DAG_STATE_SKIPPED"
            log_info "Stage '$stage_id' skipped (dependency was skipped)"
            jsonl_stage_skipped "$stage_id" "dependency_skipped" ""
            continue
        fi

        # Check if dependencies are satisfied
        if dag_exec_deps_satisfied "$stage_id"; then
            # Check condition
            local condition
            condition=$(dag_get_stage_condition "$stage_id")
            if [[ -n "$condition" ]]; then
                local condition_result=0
                dag_evaluate_condition "$condition" "$DAG_EXEC_WORKSPACE"
                condition_result=$?
                jsonl_condition_evaluated "$stage_id" "$condition" "$condition_result"

                if [[ "$condition_result" -ne 0 ]]; then
                    dag_exec_set_state "$stage_id" "$DAG_STATE_SKIPPED"
                    log_info "Stage '$stage_id' skipped (condition '$condition' evaluated false)"
                    jsonl_stage_skipped "$stage_id" "condition_false" "$condition"
                    continue
                fi
                jsonl_stage_ready "$stage_id" "$condition"
            fi

            # Check if stage is selected via CLI
            if ! is_stage_selected "$stage_id"; then
                dag_exec_set_state "$stage_id" "$DAG_STATE_SKIPPED"
                log_info "Stage '$stage_id' skipped (not in CLI_STAGES)"
                jsonl_stage_skipped "$stage_id" "cli_excluded" ""
                continue
            fi

            ready_stages+=("$stage_id")
        fi
    done

    # Return ready stages in topological order (deterministic)
    printf '%s\n' "${ready_stages[@]}"
}

# ============================================
# Find all stages that are ready to execute (populates array by reference)
# ============================================
dag_exec_get_ready_stages_into() {
    local -n ready_stages_ref="$1"
    ready_stages_ref=()
    local i
    for (( i=0; i<${#DAG_STAGE_ID[@]}; i++ )); do
        local stage_id="${DAG_STAGE_ID[i]}"
        local stage_state="${DAG_EXEC_STAGE_STATES[i]}"

        if [[ "$stage_state" != "$DAG_STATE_PENDING" ]]; then
            continue
        fi

        # Check if any dependency has failed - if so, block this stage
        if dag_exec_has_failed_deps "$stage_id"; then
            dag_exec_set_state "$stage_id" "$DAG_STATE_BLOCKED"
            log_info "Stage '$stage_id' blocked due to failed dependency"
            jsonl_stage_blocked "$stage_id" "dependency_failed"
            continue
        fi

        # Check if any dependency was skipped - if so, skip this stage too
        if dag_exec_has_skipped_deps "$stage_id"; then
            dag_exec_set_state "$stage_id" "$DAG_STATE_SKIPPED"
            log_info "Stage '$stage_id' skipped (dependency was skipped)"
            jsonl_stage_skipped "$stage_id" "dependency_skipped" ""
            continue
        fi

        # Check if dependencies are satisfied
        if dag_exec_deps_satisfied "$stage_id"; then
            # Check condition
            local condition
            condition=$(dag_get_stage_condition "$stage_id")
            if [[ -n "$condition" ]]; then
                local condition_result=0
                dag_evaluate_condition "$condition" "$DAG_EXEC_WORKSPACE"
                condition_result=$?
                jsonl_condition_evaluated "$stage_id" "$condition" "$condition_result"

                if [[ "$condition_result" -ne 0 ]]; then
                    dag_exec_set_state "$stage_id" "$DAG_STATE_SKIPPED"
                    log_info "Stage '$stage_id' skipped (condition '$condition' evaluated false)"
                    jsonl_stage_skipped "$stage_id" "condition_false" "$condition"
                    continue
                fi
                jsonl_stage_ready "$stage_id" "$condition"
            fi

            # Check if stage is selected via CLI
            if ! is_stage_selected "$stage_id"; then
                dag_exec_set_state "$stage_id" "$DAG_STATE_SKIPPED"
                log_info "Stage '$stage_id' skipped (not in CLI_STAGES)"
                jsonl_stage_skipped "$stage_id" "cli_excluded" ""
                continue
            fi

            ready_stages_ref+=("$stage_id")
        fi
    done
}

# ============================================
# Execute a single stage using existing pipeline functions
# ============================================
dag_exec_run_stage() {
    local stage_id="$1"
    local workspace="$2"

    dag_exec_set_state "$stage_id" "$DAG_STATE_RUNNING"

    # Get stage metadata
    local stage_label
    stage_label=$(dag_get_stage_label "$stage_id")
    local stage_cmd
    stage_cmd=$(dag_get_stage_cmd "$stage_id")
    local check_file
    # Use the first output as check file
    local outputs
    outputs=$(dag_get_stage_outputs "$stage_id")
    check_file="${workspace}/$(echo "$outputs" | cut -d' ' -f1)"

    log_info "Executing stage: $stage_label ($stage_id)"

    # Update manifest to running
    update_stage_manifest "$workspace" "$stage_id" "running" 0 0 1

    # Get failure policy for retry logic
    local failure_policy
    failure_policy=$(dag_get_stage_failure_policy "$stage_id")
    local max_attempts=1
    if [[ "$failure_policy" == "RETRY" ]]; then
        max_attempts=$(( STAGE_RETRIES + 1 ))
    fi

    # Execute the stage command with proper arguments
    local stage_start_epoch
    stage_start_epoch="$(date +%s%3N 2>/dev/null || date +%s)"

    local attempt=1
    local stage_status=0
    local domain="${DOMAIN:-example.com}"

    while (( attempt <= max_attempts )); do
        if (( attempt > 1 )); then
            log_warn "Retrying ${stage_label} (attempt ${attempt}/${max_attempts})..."
            update_stage_manifest "$workspace" "$stage_id" "running" 0 0 "$attempt"
        fi

        stage_status=0
        # Build command arguments based on stage
        case "$stage_id" in
            subdomains)
                local subdomain_dir="${workspace}/subdomains"
                local subfinder_output="${subdomain_dir}/subfinder.txt"
                local assetfinder_output="${subdomain_dir}/assetfinder.txt"
                if [[ "${STAGE_TIMEOUT:-0}" -gt 0 ]]; then
                    run_with_timeout "$STAGE_TIMEOUT" "$stage_cmd" "$domain" "$subdomain_dir" "$subfinder_output" "$assetfinder_output" || stage_status=$?
                else
                    "$stage_cmd" "$domain" "$subdomain_dir" "$subfinder_output" "$assetfinder_output" || stage_status=$?
                fi
                ;;
            dns)
                local merged_subdomains="${workspace}/subdomains/all.txt"
                local dns_output="${workspace}/dns/resolved.txt"
                if [[ "${STAGE_TIMEOUT:-0}" -gt 0 ]]; then
                    run_with_timeout "$STAGE_TIMEOUT" "$stage_cmd" "$domain" "$merged_subdomains" "$dns_output" || stage_status=$?
                else
                    "$stage_cmd" "$domain" "$merged_subdomains" "$dns_output" || stage_status=$?
                fi
                ;;
            ports)
                local dns_output="${workspace}/dns/resolved.txt"
                local ports_output="${workspace}/ports/naabu.txt"
                if [[ "${STAGE_TIMEOUT:-0}" -gt 0 ]]; then
                    run_with_timeout "$STAGE_TIMEOUT" "$stage_cmd" "$domain" "$dns_output" "$ports_output" || stage_status=$?
                else
                    "$stage_cmd" "$domain" "$dns_output" "$ports_output" || stage_status=$?
                fi
                ;;
            live)
                local dns_output="${workspace}/dns/resolved.txt"
                local web_candidates="${workspace}/ports/web_candidates.txt"
                local http_targets="${workspace}/live/targets.txt"
                local live_output="${workspace}/live/httpx.txt"
                local clean_urls="${workspace}/live/urls.txt"
                if [[ "${STAGE_TIMEOUT:-0}" -gt 0 ]]; then
                    run_with_timeout "$STAGE_TIMEOUT" "$stage_cmd" "$domain" "$dns_output" "$web_candidates" "$http_targets" "$live_output" "$clean_urls" || stage_status=$?
                else
                    "$stage_cmd" "$domain" "$dns_output" "$web_candidates" "$http_targets" "$live_output" "$clean_urls" || stage_status=$?
                fi
                ;;
            crawling)
                local clean_urls="${workspace}/live/urls.txt"
                local katana_output="${workspace}/urls/katana.txt"
                if [[ "${STAGE_TIMEOUT:-0}" -gt 0 ]]; then
                    run_with_timeout "$STAGE_TIMEOUT" "$stage_cmd" "$domain" "$clean_urls" "$katana_output" || stage_status=$?
                else
                    "$stage_cmd" "$domain" "$clean_urls" "$katana_output" || stage_status=$?
                fi
                ;;
            vuln)
                local katana_output="${workspace}/urls/katana.txt"
                local clean_urls="${workspace}/live/urls.txt"
                local nuclei_output="${workspace}/nuclei/findings.jsonl"
                if [[ "${STAGE_TIMEOUT:-0}" -gt 0 ]]; then
                    run_with_timeout "$STAGE_TIMEOUT" "$stage_cmd" "$domain" "$katana_output" "$clean_urls" "$nuclei_output" || stage_status=$?
                else
                    "$stage_cmd" "$domain" "$katana_output" "$clean_urls" "$nuclei_output" || stage_status=$?
                fi
                ;;
            reports)
                if [[ "${STAGE_TIMEOUT:-0}" -gt 0 ]]; then
                    run_with_timeout "$STAGE_TIMEOUT" "$stage_cmd" "$workspace" "$domain" || stage_status=$?
                else
                    "$stage_cmd" "$workspace" "$domain" || stage_status=$?
                fi
                ;;
            *)
                # Fallback: try calling command directly
                if [[ "${STAGE_TIMEOUT:-0}" -gt 0 ]]; then
                    run_with_timeout "$STAGE_TIMEOUT" "$stage_cmd" || stage_status=$?
                else
                    "$stage_cmd" || stage_status=$?
                fi
                ;;
        esac

        if [[ "$stage_status" -eq 0 ]]; then
            break
        fi

        attempt=$(( attempt + 1 ))
    done

    local stage_end_epoch
    stage_end_epoch="$(date +%s%3N 2>/dev/null || date +%s)"
    local duration=$(( stage_end_epoch - stage_start_epoch ))

    if [[ "$stage_status" -eq 0 ]]; then
        local output_count=0
        if [[ -f "$check_file" ]]; then
            output_count="$(count_result_lines "$check_file" 2>/dev/null || echo 0)"
        fi
        update_stage_manifest "$workspace" "$stage_id" "success" "$duration" "$output_count" "$attempt"
        dag_exec_set_state "$stage_id" "$DAG_STATE_SUCCESS"
        log_success "Stage '$stage_label' completed successfully"
        jsonl_stage_complete "$stage_id" "success" "$duration" "$output_count"
        return 0
    else
        update_stage_manifest "$workspace" "$stage_id" "failed" "$duration" 0 "$attempt"
        dag_exec_set_state "$stage_id" "$DAG_STATE_FAILED"
        log_error "Stage '$stage_label' failed with status $stage_status"
        jsonl_stage_complete "$stage_id" "failed" "$duration" "0"
        return "$stage_status"
    fi
}

# ============================================
# Handle stage failure according to failure policy
# ============================================
dag_exec_handle_failure() {
    local stage_id="$1"
    local failure_policy
    failure_policy=$(dag_get_stage_failure_policy "$stage_id")

    case "$failure_policy" in
        FAIL_FAST)
            log_error "FAIL_FAST: DAG execution aborted due to failure in '$stage_id'"
            # Mark all pending dependents as BLOCKED
            dag_exec_block_dependents_with_telemetry "$stage_id"
            ;;
        CONTINUE)
            log_warn "CONTINUE: Stage '$stage_id' failed, continuing with independent stages"
            # Block dependents but don't abort
            dag_exec_block_dependents_with_telemetry "$stage_id"
            ;;
        SKIP_DEPENDENTS)
            log_warn "SKIP_DEPENDENTS: Stage '$stage_id' failed, blocking dependents"
            dag_exec_block_dependents_with_telemetry "$stage_id"
            ;;
        RETRY)
            # Retry is handled by run_pipeline_stage internally
            log_warn "RETRY: Stage '$stage_id' failed, retries exhausted"
            ;;
        *)
            log_error "Unknown failure policy: $failure_policy"
            ;;
    esac
}

# ============================================
# Block all dependents of a failed stage (with telemetry)
# ============================================
dag_exec_block_dependents_with_telemetry() {
    local failed_stage="$1"
    local i
    for (( i=0; i<${#DAG_STAGE_ID[@]}; i++ )); do
        local stage_id="${DAG_STAGE_ID[i]}"
        local stage_state="${DAG_EXEC_STAGE_STATES[i]}"

        if [[ "$stage_state" == "$DAG_STATE_PENDING" ]]; then
            local deps
            deps=$(dag_get_stage_deps "$stage_id")
            if [[ -n "$deps" ]]; then
                local IFS=','
                read -r -a dep_array <<< "$deps"
                local dep
                for dep in "${dep_array[@]}"; do
                    dep="${dep// /}"
                    if [[ "$dep" == "$failed_stage" ]]; then
                        dag_exec_set_state "$stage_id" "$DAG_STATE_BLOCKED"
                        log_info "Stage '$stage_id' blocked (depends on failed stage '$failed_stage')"
                        jsonl_stage_blocked "$stage_id" "$failed_stage"
                        break
                    fi
                done
            fi
        fi
    done
}

# ============================================
# Check if DAG execution is complete
# ============================================
dag_exec_is_complete() {
    local i
    local has_pending=0
    local has_running=0

    for (( i=0; i<${#DAG_STAGE_ID[@]}; i++ )); do
        local state="${DAG_EXEC_STAGE_STATES[i]}"
        if [[ "$state" == "$DAG_STATE_PENDING" ]]; then
            has_pending=1
        elif [[ "$state" == "$DAG_STATE_RUNNING" ]]; then
            has_running=1
        fi
    done

    if (( has_pending == 0 && has_running == 0 )); then
        return 0  # Complete
    fi
    return 1  # Still running
}

# ============================================
# Check if DAG execution has failed (FAIL_FAST or critical failure)
# ============================================
dag_exec_has_critical_failure() {
    local i
    for (( i=0; i<${#DAG_STAGE_ID[@]}; i++ )); do
        local stage_id="${DAG_STAGE_ID[i]}"
        local state="${DAG_EXEC_STAGE_STATES[i]}"
        if [[ "$state" == "$DAG_STATE_FAILED" ]]; then
            local failure_policy
            failure_policy=$(dag_get_stage_failure_policy "$stage_id")
            if [[ "$failure_policy" == "FAIL_FAST" ]]; then
                return 0
            fi
        fi
    done
    return 1
}

# ============================================
# Main DAG execution loop
# ============================================
dag_exec_execute() {
    local workspace="$1"

    if ! dag_exec_init "$workspace"; then
        return 1
    fi

    local execution_failed=0
    local fail_fast_triggered=0

    # Main execution loop
    while ! dag_exec_is_complete; do
        # Check for critical failure
        if dag_exec_has_critical_failure; then
            fail_fast_triggered=1
            execution_failed=1
            break
        fi

        # Get ready stages (use function directly, not subshell)
        local ready_stages=()
        dag_exec_get_ready_stages_into ready_stages

        if (( ${#ready_stages[@]} == 0 )); then
            # No ready stages but not complete - check if there are pending stages blocked
            local has_pending=0
            local i
            for (( i=0; i<${#DAG_STAGE_ID[@]}; i++ )); do
                if [[ "${DAG_EXEC_STAGE_STATES[i]}" == "$DAG_STATE_PENDING" ]]; then
                    has_pending=1
                    break
                fi
            done

            if (( has_pending == 0 )); then
                # All remaining are BLOCKED/SKIPPED - execution complete
                break
            fi

            # No progress possible - deadlock or error
            log_error "No ready stages but DAG not complete - possible deadlock"
            execution_failed=1
            break
        fi

        # Execute ready stages sequentially (deterministic order from topological sort)
        local stage_id
        for stage_id in "${ready_stages[@]}"; do
            if ! dag_exec_run_stage "$stage_id" "$workspace"; then
                # Stage failed - handle according to policy
                local failure_policy
                failure_policy=$(dag_get_stage_failure_policy "$stage_id")
                dag_exec_handle_failure "$stage_id"
                execution_failed=1
                # Check if FAIL_FAST
                if [[ "$failure_policy" == "FAIL_FAST" ]]; then
                    fail_fast_triggered=1
                    break
                fi
            fi
        done

        if (( fail_fast_triggered )); then
            break
        fi
    done

    # Determine overall result
    if (( fail_fast_triggered )); then
        log_error "DAG execution aborted (FAIL_FAST)"
        return 2
    elif (( execution_failed )); then
        log_error "DAG execution completed with failures"
        return 1
    else
        log_success "DAG execution completed successfully"
        return 0
    fi
}

# ============================================
# Get execution summary
# ============================================
dag_exec_summary() {
    local i
    echo "DAG Execution Summary:"
    for (( i=0; i<${#DAG_STAGE_ID[@]}; i++ )); do
        local stage_id="${DAG_STAGE_ID[i]}"
        local state="${DAG_EXEC_STAGE_STATES[i]}"
        printf "  %s: %s\n" "$stage_id" "$state"
    done
}

# ============================================
# Export variables
# ============================================
export DAG_STATE_PENDING
export DAG_STATE_READY
export DAG_STATE_RUNNING
export DAG_STATE_SUCCESS
export DAG_STATE_FAILED
export DAG_STATE_BLOCKED
export DAG_STATE_SKIPPED