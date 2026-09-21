#!/usr/bin/env bash

# ============================================
# Recon Framework - Manifest & Pipeline State
# ============================================

MANIFEST_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v log_debug >/dev/null 2>&1; then
    # shellcheck source=./logger.sh
    source "$MANIFEST_LIB_DIR/logger.sh"
fi

# Canonical stages list
MANIFEST_CANONICAL_STAGES=("subdomains" "dns" "ports" "live" "crawling" "vuln" "reports")

# Detect available JSON processing engine
_detect_json_engine() {
    if command -v jq >/dev/null 2>&1 && jq --version >/dev/null 2>&1; then
        echo "jq"
    elif python3 -c "import json" >/dev/null 2>&1; then
        echo "python3"
    elif python -c "import json" >/dev/null 2>&1; then
        echo "python"
    else
        echo "fallback"
    fi
}

# Validate whether a file contains valid JSON
validate_json_file() {
    local json_file="$1"
    if [[ ! -f "$json_file" || ! -s "$json_file" ]]; then
        return 1
    fi

    local engine
    engine="$(_detect_json_engine)"

    case "$engine" in
        jq)
            jq empty "$json_file" >/dev/null 2>&1
            return $?
            ;;
        python3)
            python3 -c "import json, sys; json.load(open(sys.argv[1], encoding='utf-8'))" "$json_file" >/dev/null 2>&1
            return $?
            ;;
        python)
            python -c "import json, sys; json.load(open(sys.argv[1], encoding='utf-8'))" "$json_file" >/dev/null 2>&1
            return $?
            ;;
        *)
            local first_char last_char
            first_char="$(head -c 1 "$json_file" 2>/dev/null || true)"
            last_char="$(tail -c 2 "$json_file" 2>/dev/null | tr -d '\n\r ' || true)"
            [[ "$first_char" == "{" && "$last_char" == "}" ]]
            return $?
            ;;
    esac
}

# Escape arbitrary string for safe JSON inclusion
escape_json_string() {
    local raw="$1"
    local s="${raw//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

# Atomically replace target file with candidate only if candidate is valid JSON
atomic_swap_manifest() {
    local temp_file="$1"
    local target_file="$2"

    if [[ ! -f "$temp_file" ]]; then
        log_error "Manifest candidate temp file missing: $temp_file"
        return 1
    fi

    if ! validate_json_file "$temp_file"; then
        log_error "Manifest update rejected: candidate is not valid JSON ($temp_file)"
        rm -f "$temp_file" 2>/dev/null || true
        return 1
    fi

    if ! mv -f "$temp_file" "$target_file"; then
        log_error "Failed to atomically replace manifest file: $target_file"
        rm -f "$temp_file" 2>/dev/null || true
        return 1
    fi

    return 0
}

# Read stage status from manifest.json
# Usage: get_manifest_stage_status "$workspace" "$stage"
get_manifest_stage_status() {
    local workspace="$1"
    local stage="$2"
    local manifest_file="${workspace}/manifest.json"

    if [[ ! -f "$manifest_file" ]]; then
        echo "unknown"
        return 1
    fi

    local engine
    engine="$(_detect_json_engine)"

    case "$engine" in
        jq)
            local st
            st="$(jq -r --arg s "$stage" '.stages[$s].status // empty' "$manifest_file" 2>/dev/null)"
            if [[ -n "$st" ]]; then
                echo "$st"
                return 0
            fi
            ;;
        python3|python)
            local st
            st="$("$engine" -c '
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        d = json.load(f)
    print(d.get("stages", {}).get(sys.argv[2], {}).get("status", ""))
except Exception:
    pass
' "$manifest_file" "$stage" 2>/dev/null)"
            if [[ -n "$st" ]]; then
                echo "$st"
                return 0
            fi
            ;;
    esac

    local raw_status
    raw_status="$(grep -E "\"${stage}\":[[:space:]]*\{" "$manifest_file" 2>/dev/null | grep -o -E '"status":[[:space:]]*"[^"]+"' | head -n 1 | cut -d'"' -f4 || true)"
    if [[ -n "$raw_status" ]]; then
        echo "$raw_status"
        return 0
    fi

    echo "unknown"
    return 1
}

# Read overall manifest status
# Usage: get_manifest_overall_status "$workspace"
get_manifest_overall_status() {
    local workspace="$1"
    local manifest_file="${workspace}/manifest.json"

    if [[ ! -f "$manifest_file" ]]; then
        echo "unknown"
        return 1
    fi

    local engine
    engine="$(_detect_json_engine)"

    case "$engine" in
        jq)
            local st
            st="$(jq -r '.status // empty' "$manifest_file" 2>/dev/null)"
            if [[ -n "$st" ]]; then
                echo "$st"
                return 0
            fi
            ;;
        python3|python)
            local st
            st="$("$engine" -c '
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        d = json.load(f)
    print(d.get("status", ""))
except Exception:
    pass
' "$manifest_file" 2>/dev/null)"
            if [[ -n "$st" ]]; then
                echo "$st"
                return 0
            fi
            ;;
    esac

    local raw_status
    raw_status="$(grep -E '^[[:space:]]*"status":' "$manifest_file" 2>/dev/null | head -n 1 | cut -d'"' -f4 || true)"
    if [[ -n "$raw_status" ]]; then
        echo "$raw_status"
        return 0
    fi

    echo "unknown"
    return 1
}

# Initialize manifest.json for a workspace
init_manifest() {
    local workspace="$1"
    local domain="$2"
    local threads="${3:-50}"
    local rate_limit="${4:-150}"
    local timeout="${5:-300}"
    local retries="${6:-1}"
    local resume_val="${7:-0}"
    local stages_sel="${8:-all}"
    local stages_skip="${9:-}"

    local manifest_file="${workspace}/manifest.json"
    local start_time
    start_time="$(date +"%Y-%m-%d %H:%M:%S" 2>/dev/null || date)"

    local resume_bool="false"
    if [[ "$resume_val" == "1" || "$resume_val" == "true" ]]; then
        resume_bool="true"
    fi

    # In resumption mode with an existing manifest, preserve previous stage state
    if [[ "$resume_bool" == "true" && -f "$manifest_file" ]]; then
        local temp_manifest
        temp_manifest="$(mktemp "${manifest_file}.tmp.XXXXXX" 2>/dev/null || printf '%s.tmp.%s' "$manifest_file" "$$")"
        sed -E \
            -e 's/^[[:space:]]*"status":[[:space:]]*"[^"]*"/  "status": "running"/' \
            -e 's/"end_time":[[:space:]]*"[^"]*"/"end_time": null/' \
            -e 's/"resume":[[:space:]]*(false|true)/"resume": true/' \
            "$manifest_file" > "$temp_manifest" 2>/dev/null || true

        if validate_json_file "$temp_manifest"; then
            atomic_swap_manifest "$temp_manifest" "$manifest_file"
            log_debug "Resumed existing manifest for $domain: $manifest_file"
            return 0
        fi
        rm -f "$temp_manifest" 2>/dev/null || true
    fi

    local safe_domain
    safe_domain="$(escape_json_string "$domain")"
    local safe_sel
    safe_sel="$(escape_json_string "$stages_sel")"
    local safe_skip
    safe_skip="$(escape_json_string "$stages_skip")"

    local temp_manifest
    temp_manifest="$(mktemp "${manifest_file}.tmp.XXXXXX" 2>/dev/null || printf '%s.tmp.%s' "$manifest_file" "$$")"

    # Build initial JSON into candidate file
    {
        printf '{\n'
        printf '  "target": "%s",\n' "$safe_domain"
        printf '  "start_time": "%s",\n' "$start_time"
        printf '  "end_time": null,\n'
        printf '  "status": "running",\n'
        printf '  "config": {\n'
        printf '    "threads": %d,\n' "$threads"
        printf '    "rate_limit": %d,\n' "$rate_limit"
        printf '    "timeout": %d,\n' "$timeout"
        printf '    "retries": %d,\n' "$retries"
        printf '    "resume": %s,\n' "$resume_bool"
        printf '    "stages_selected": "%s",\n' "$safe_sel"
        printf '    "stages_skipped": "%s"\n' "$safe_skip"
        printf '  },\n'
        printf '  "stages": {\n'

        local i=0
        local total=${#MANIFEST_CANONICAL_STAGES[@]}
        for s in "${MANIFEST_CANONICAL_STAGES[@]}"; do
            i=$(( i + 1 ))
            printf '    "%s": { "status": "pending", "duration_seconds": 0, "output_count": 0, "attempts": 0 }' "$s"
            if (( i < total )); then
                printf ',\n'
            else
                printf '\n'
            fi
        done

        printf '  }\n'
        printf '}\n'
    } > "$temp_manifest"

    if ! atomic_swap_manifest "$temp_manifest" "$manifest_file"; then
        return 1
    fi

    log_debug "Initialized manifest: $manifest_file"
    return 0
}

# Update a single stage status in manifest.json
# Usage: update_stage_manifest "$workspace" "$stage" "$status" [duration_seconds] [output_count] [attempts]
update_stage_manifest() {
    local workspace="$1"
    local stage="$2"
    local status="$3"
    local duration="${4:-0}"
    local count="${5:-0}"
    local attempts="${6:-1}"

    local manifest_file="${workspace}/manifest.json"
    if [[ ! -f "$manifest_file" ]]; then
        return 0
    fi

    [[ "$duration" =~ ^[0-9]+$ ]] || duration=0
    [[ "$count" =~ ^[0-9]+$ ]] || count=0
    [[ "$attempts" =~ ^[0-9]+$ ]] || attempts=1

    local temp_manifest
    temp_manifest="$(mktemp "${manifest_file}.tmp.XXXXXX" 2>/dev/null || printf '%s.tmp.%s' "$manifest_file" "$$")"

    local safe_status
    safe_status="$(escape_json_string "$status")"

    # Precise single-line replacement preserving canonical layout
    sed -E "s/\"${stage}\":[[:space:]]*\{[^\}]*\}/\"${stage}\": { \"status\": \"${safe_status}\", \"duration_seconds\": ${duration}, \"output_count\": ${count}, \"attempts\": ${attempts} }/" "$manifest_file" > "$temp_manifest" 2>/dev/null || true

    # If sed failed or produced invalid JSON, fallback to Python / jq AST mutation
    if ! validate_json_file "$temp_manifest"; then
        local engine
        engine="$(_detect_json_engine)"
        case "$engine" in
            jq)
                jq --arg st "$stage" \
                   --arg stat "$status" \
                   --argjson dur "$duration" \
                   --argjson cnt "$count" \
                   --argjson att "$attempts" \
                   '.stages[$st] = { "status": $stat, "duration_seconds": $dur, "output_count": $cnt, "attempts": $att }' \
                   "$manifest_file" > "$temp_manifest" 2>/dev/null || true
                ;;
            python3|python)
                "$engine" -c '
import json, sys
manifest_path, stage, status, dur, cnt, att, out_path = sys.argv[1:8]
with open(manifest_path, "r", encoding="utf-8") as f:
    data = json.load(f)
if "stages" not in data:
    data["stages"] = {}
data["stages"][stage] = {
    "status": status,
    "duration_seconds": int(dur),
    "output_count": int(cnt),
    "attempts": int(att)
}
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
' "$manifest_file" "$stage" "$status" "$duration" "$count" "$attempts" "$temp_manifest" 2>/dev/null || true
                ;;
        esac
    fi

    if ! atomic_swap_manifest "$temp_manifest" "$manifest_file"; then
        return 1
    fi

    log_debug "Manifest updated: stage '$stage' -> '$status' (duration: ${duration}s, count: $count, attempts: $attempts)"
    return 0
}

# Finalize manifest with overall status and completion timestamp
finalize_manifest() {
    local workspace="$1"
    local overall_status="$2"

    local manifest_file="${workspace}/manifest.json"
    if [[ ! -f "$manifest_file" ]]; then
        return 0
    fi

    local end_time
    end_time="$(date +"%Y-%m-%d %H:%M:%S" 2>/dev/null || date)"

    local safe_status
    safe_status="$(escape_json_string "$overall_status")"

    local temp_manifest
    temp_manifest="$(mktemp "${manifest_file}.tmp.XXXXXX" 2>/dev/null || printf '%s.tmp.%s' "$manifest_file" "$$")"

    # Replace end_time and top-level status only
    sed -E \
        -e "s/\"end_time\":[[:space:]]*(null|\"[^\"]*\")/\"end_time\": \"${end_time}\"/" \
        -e "s/^[[:space:]]*\"status\":[[:space:]]*\"[^\"]*\"/  \"status\": \"${safe_status}\"/" \
        "$manifest_file" > "$temp_manifest" 2>/dev/null || true

    if ! validate_json_file "$temp_manifest"; then
        local engine
        engine="$(_detect_json_engine)"
        case "$engine" in
            jq)
                jq --arg stat "$overall_status" \
                   --arg et "$end_time" \
                   '.status = $stat | .end_time = $et' \
                   "$manifest_file" > "$temp_manifest" 2>/dev/null || true
                ;;
            python3|python)
                "$engine" -c '
import json, sys
manifest_path, status, end_time, out_path = sys.argv[1:5]
with open(manifest_path, "r", encoding="utf-8") as f:
    data = json.load(f)
data["status"] = status
data["end_time"] = end_time
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
' "$manifest_file" "$overall_status" "$end_time" "$temp_manifest" 2>/dev/null || true
                ;;
        esac
    fi

    if ! atomic_swap_manifest "$temp_manifest" "$manifest_file"; then
        return 1
    fi

    log_debug "Finalized manifest: status '$overall_status', end_time: $end_time"
    return 0
}
