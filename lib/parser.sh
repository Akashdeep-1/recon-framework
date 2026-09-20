#!/usr/bin/env bash

# ============================================
# Recon Framework - Normalized Parser Library
# ============================================

PARSER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v log_error >/dev/null 2>&1; then
    # shellcheck source=./logger.sh
    source "$PARSER_LIB_DIR/logger.sh"
fi
if ! command -v normalize_domain >/dev/null 2>&1; then
    # shellcheck source=./validation.sh
    source "$PARSER_LIB_DIR/validation.sh"
fi

# Escape JSON string values safely in pure bash
_json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

# Normalize hosts list into JSONL: {"host":"...","target":"...","source":"..."}
parse_hosts_jsonl() {
    local input_file="$1"
    local output_jsonl="$2"
    local target_domain="$3"
    local source_label="${4:-subdomain}"

    if [[ ! -f "$input_file" ]]; then
        return 1
    fi

    local norm_target
    norm_target="$(normalize_domain "$target_domain")"
    : > "$output_jsonl"

    while IFS= read -r host || [[ -n "$host" ]]; do
        host="$(normalize_domain "$host")"
        if [[ -z "$host" || "$host" == \#* ]]; then
            continue
        fi

        local esc_host esc_target esc_source
        esc_host="$(_json_escape "$host")"
        esc_target="$(_json_escape "$norm_target")"
        esc_source="$(_json_escape "$source_label")"

        printf '{"host":"%s","target":"%s","source":"%s"}\n' \
            "$esc_host" "$esc_target" "$esc_source" >> "$output_jsonl"
    done < "$input_file"

    return 0
}

# Parse DNSX output into hosts/IPs JSONL: {"host":"...","ip":"...","target":"..."}
# Supports both "host" and "host [ip, ip2]" formats
parse_dnsx_output() {
    local input_file="$1"
    local output_jsonl="$2"
    local target_domain="$3"

    if [[ ! -f "$input_file" ]]; then
        return 1
    fi

    local norm_target
    norm_target="$(normalize_domain "$target_domain")"
    : > "$output_jsonl"

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        if [[ -z "$line" || "$line" == \#* ]]; then
            continue
        fi

        local host ip=""
        if [[ "$line" =~ ^([^[:space:]]+)[[:space:]]+\[([^\]]+)\] ]]; then
            host="${BASH_REMATCH[1]}"
            ip="${BASH_REMATCH[2]}"
        else
            host="$line"
        fi

        host="$(normalize_domain "$host")"
        if [[ -z "$host" ]]; then
            continue
        fi

        local esc_host esc_ip esc_target
        esc_host="$(_json_escape "$host")"
        esc_ip="$(_json_escape "$ip")"
        esc_target="$(_json_escape "$norm_target")"

        printf '{"host":"%s","ip":"%s","target":"%s"}\n' \
            "$esc_host" "$esc_ip" "$esc_target" >> "$output_jsonl"
    done < "$input_file"

    return 0
}

# Parse Naabu open ports output: host:port -> JSONL {"host":"...","port":...,"protocol":"tcp","target":"..."}
parse_naabu_output() {
    local input_file="$1"
    local output_jsonl="$2"
    local target_domain="$3"

    if [[ ! -f "$input_file" ]]; then
        return 1
    fi

    local norm_target
    norm_target="$(normalize_domain "$target_domain")"
    : > "$output_jsonl"

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        if [[ -z "$line" || "$line" == \#* ]]; then
            continue
        fi

        local host port
        if [[ "$line" == *:* ]]; then
            host="${line%:*}"
            port="${line##*:}"
        else
            continue
        fi

        host="$(normalize_domain "$host")"
        if [[ -z "$host" || ! "$port" =~ ^[0-9]+$ ]]; then
            continue
        fi

        local esc_host esc_target
        esc_host="$(_json_escape "$host")"
        esc_target="$(_json_escape "$norm_target")"

        printf '{"host":"%s","port":%d,"protocol":"tcp","target":"%s"}\n' \
            "$esc_host" "$port" "$esc_target" >> "$output_jsonl"
    done < "$input_file"

    return 0
}

# Extract candidate web endpoints (host:port) from Naabu results matching web ports
extract_web_ports_from_naabu() {
    local input_file="$1"
    local output_file="$2"
    local target_domain="$3"
    local web_ports_csv="${4:-80,443,8000,8080,8443,8888,9000,9443,3000,5000}"

    if [[ ! -f "$input_file" ]]; then
        : > "$output_file"
        return 0
    fi

    local norm_target
    norm_target="$(normalize_domain "$target_domain")"
    local temp_out
    temp_out="$(mktemp "${output_file}.tmp.XXXXXX" 2>/dev/null || printf '%s.tmp' "$output_file")"

    # Convert comma-separated web ports into an array
    local IFS=','
    read -r -a allowed_ports <<< "$web_ports_csv"

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        if [[ -z "$line" || "$line" == \#* ]]; then
            continue
        fi

        local host port
        if [[ "$line" == *:* ]]; then
            host="${line%:*}"
            port="${line##*:}"
        else
            continue
        fi

        host="$(normalize_domain "$host")"
        if [[ -z "$host" || ! "$port" =~ ^[0-9]+$ ]]; then
            continue
        fi

        # Scope enforcement
        if ! is_in_scope "$host" "$norm_target"; then
            continue
        fi

        # Check if port is an allowed web port
        local is_web=0
        local p
        for p in "${allowed_ports[@]}"; do
            p="${p// /}"
            if [[ "$p" == "$port" ]]; then
                is_web=1
                break
            fi
        done

        if (( is_web == 1 )); then
            # Format as host:port for HTTP probing
            if [[ "$port" == "80" || "$port" == "443" ]]; then
                printf '%s\n' "$host" >> "$temp_out"
            else
                printf '%s:%s\n' "$host" "$port" >> "$temp_out"
            fi
        fi
    done < "$input_file"

    if [[ -f "$temp_out" ]]; then
        sort -u "$temp_out" > "$output_file"
        rm -f "$temp_out"
    else
        : > "$output_file"
    fi

    return 0
}

# Parse Katana discovered URLs into JSONL: {"url":"...","host":"...","target":"...","source":"katana"}
parse_katana_output() {
    local input_file="$1"
    local output_jsonl="$2"
    local target_domain="$3"

    if [[ ! -f "$input_file" ]]; then
        return 1
    fi

    local norm_target
    norm_target="$(normalize_domain "$target_domain")"
    : > "$output_jsonl"

    while IFS= read -r url || [[ -n "$url" ]]; do
        url="${url#"${url%%[![:space:]]*}"}"
        url="${url%"${url##*[![:space:]]}"}"
        if [[ -z "$url" || "$url" == \#* ]]; then
            continue
        fi

        # Extract host from URL
        local host_part="${url#http://}"
        host_part="${host_part#https://}"
        host_part="${host_part%%/*}"
        host_part="${host_part%%\?*}"
        host_part="${host_part%%\#*}"
        host_part="${host_part%%:*}"
        host_part="$(normalize_domain "$host_part")"

        local esc_url esc_host esc_target
        esc_url="$(_json_escape "$url")"
        esc_host="$(_json_escape "$host_part")"
        esc_target="$(_json_escape "$norm_target")"

        printf '{"url":"%s","host":"%s","target":"%s","source":"katana"}\n' \
            "$esc_url" "$esc_host" "$esc_target" >> "$output_jsonl"
    done < "$input_file"

    return 0
}

# Summarize Nuclei JSONL findings into a metrics JSON file
parse_nuclei_findings() {
    local input_jsonl="$1"
    local summary_file="$2"
    local target_domain="$3"

    local norm_target
    norm_target="$(normalize_domain "$target_domain")"

    local total=0 crit=0 high=0 med=0 low=0 info=0

    if [[ -f "$input_jsonl" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ -z "$line" ]]; then
                continue
            fi
            total=$(( total + 1 ))

            # Extract severity using pattern match on json line
            if [[ "$line" =~ \"severity\":[[:space:]]*\"([^\"]+)\" ]]; then
                local sev
                sev="$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')"
                case "$sev" in
                    critical) crit=$(( crit + 1 )) ;;
                    high)     high=$(( high + 1 )) ;;
                    medium)   med=$(( med + 1 ))  ;;
                    low)      low=$(( low + 1 ))   ;;
                    info)     info=$(( info + 1 )) ;;
                esac
            fi
        done < "$input_jsonl"
    fi

    cat << EOF > "$summary_file"
{
  "target": "$norm_target",
  "total_findings": $total,
  "severity_breakdown": {
    "critical": $crit,
    "high": $high,
    "medium": $med,
    "low": $low,
    "info": $info
  }
}
EOF

    return 0
}
