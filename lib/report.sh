#!/usr/bin/env bash

# ============================================
# Recon Framework - Reporting Library
# ============================================

REPORT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v log_error >/dev/null 2>&1; then
    # shellcheck source=./logger.sh
    source "$REPORT_LIB_DIR/logger.sh"
fi

# Count lines safely in an optional file
_safe_line_count() {
    local f="$1"
    if [[ -f "$f" ]]; then
        wc -l < "$f" | tr -d ' '
    else
        echo "0"
    fi
}

# Generate Markdown reconnaissance summary report
generate_markdown_report() {
    local workspace="$1"
    local domain="$2"
    local output_md="$3"

    local subdomains_count resolved_count ports_count urls_count live_count findings_count
    subdomains_count="$(_safe_line_count "${workspace}/subdomains/all.txt")"
    resolved_count="$(_safe_line_count "${workspace}/dns/resolved.txt")"
    ports_count="$(_safe_line_count "${workspace}/ports/naabu.txt")"
    live_count="$(_safe_line_count "${workspace}/live/urls.txt")"
    urls_count="$(_safe_line_count "${workspace}/urls/katana.txt")"
    findings_count="$(_safe_line_count "${workspace}/nuclei/findings.jsonl")"

    local scan_date
    scan_date="$(date +"%Y-%m-%d %H:%M:%S" 2>/dev/null || date)"

    cat << EOF > "$output_md"
# Reconnaissance Assessment Report: ${domain}

**Target Domain:** \`${domain}\`<br>
**Generated:** \`${scan_date}\`<br>
**Tool:** Recon Framework v${FRAMEWORK_VERSION}

---

## Executive Summary

| Stage | Finding Type | Total Count |
| :--- | :--- | :--- |
| **Subdomains** | Discovered in-scope subdomains | \`${subdomains_count}\` |
| **DNS Resolution** | Confirmed live hostnames | \`${resolved_count}\` |
| **Port Scanning** | Open service ports | \`${ports_count}\` |
| **HTTP Probing** | Active HTTP/HTTPS endpoints | \`${live_count}\` |
| **Web Crawling** | Discovered application endpoints | \`${urls_count}\` |
| **Vulnerability Scanning** | Nuclei potential findings | \`${findings_count}\` |

---

## Discovered Assets

### Live HTTP Services (Sample up to 10)
EOF

    if [[ -f "${workspace}/live/urls.txt" && -s "${workspace}/live/urls.txt" ]]; then
        sed 's/^/- /' "${workspace}/live/urls.txt" | head -n 10 >> "$output_md"
    else
        echo "_No live HTTP services recorded._" >> "$output_md"
    fi

    cat << EOF >> "$output_md"

### Open Ports (Sample up to 10)
EOF

    if [[ -f "${workspace}/ports/naabu.txt" && -s "${workspace}/ports/naabu.txt" ]]; then
        sed 's/^/- /' "${workspace}/ports/naabu.txt" | head -n 10 >> "$output_md"
    else
        echo "_No open ports recorded._" >> "$output_md"
    fi

    cat << EOF >> "$output_md"

---
*Notice: This report was generated for authorized security assessment purposes only.*
EOF

    log_success "Markdown report generated: $output_md"
    return 0
}

# Generate standalone HTML report
generate_html_report() {
    local workspace="$1"
    local domain="$2"
    local output_html="$3"

    local subdomains_count resolved_count ports_count urls_count live_count findings_count
    subdomains_count="$(_safe_line_count "${workspace}/subdomains/all.txt")"
    resolved_count="$(_safe_line_count "${workspace}/dns/resolved.txt")"
    ports_count="$(_safe_line_count "${workspace}/ports/naabu.txt")"
    live_count="$(_safe_line_count "${workspace}/live/urls.txt")"
    urls_count="$(_safe_line_count "${workspace}/urls/katana.txt")"
    findings_count="$(_safe_line_count "${workspace}/nuclei/findings.jsonl")"

    local scan_date
    scan_date="$(date +"%Y-%m-%d %H:%M:%S" 2>/dev/null || date)"

    cat << EOF > "$output_html"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Recon Report - ${domain}</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #0f172a; color: #f8fafc; margin: 0; padding: 2rem; }
        .container { max-width: 960px; margin: 0 auto; background: #1e293b; border-radius: 8px; padding: 2rem; box-shadow: 0 4px 6px -1px rgba(0,0,0,0.5); }
        h1 { color: #38bdf8; margin-top: 0; }
        .meta { color: #94a3b8; margin-bottom: 2rem; font-size: 0.9rem; }
        .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap: 1rem; margin-bottom: 2rem; }
        .card { background: #334155; padding: 1.2rem; border-radius: 6px; text-align: center; }
        .card .num { font-size: 1.8rem; font-weight: bold; color: #38bdf8; }
        .card .label { font-size: 0.85rem; color: #cbd5e1; margin-top: 0.4rem; }
        table { width: 100%; border-collapse: collapse; margin-top: 1rem; }
        th, td { text-align: left; padding: 0.75rem; border-bottom: 1px solid #475569; }
        th { color: #94a3b8; }
        footer { margin-top: 2rem; font-size: 0.8rem; color: #64748b; text-align: center; }
    </style>
</head>
<body>
<div class="container">
    <h1>Reconnaissance Report</h1>
    <div class="meta">Target: <strong>${domain}</strong> | Scan Date: ${scan_date}</div>

    <div class="grid">
        <div class="card"><div class="num">${subdomains_count}</div><div class="label">Subdomains</div></div>
        <div class="card"><div class="num">${resolved_count}</div><div class="label">Resolved Hosts</div></div>
        <div class="card"><div class="num">${ports_count}</div><div class="label">Open Ports</div></div>
        <div class="card"><div class="num">${live_count}</div><div class="label">Live Services</div></div>
        <div class="card"><div class="num">${urls_count}</div><div class="label">Crawled URLs</div></div>
        <div class="card"><div class="num">${findings_count}</div><div class="label">Findings</div></div>
    </div>

    <footer>Generated by Recon Framework. For authorized security assessments only.</footer>
</div>
</body>
</html>
EOF

    log_success "HTML report generated: $output_html"
    return 0
}

# Generate all report artifacts
generate_reports() {
    local workspace="$1"
    local domain="$2"

    local reports_dir="${workspace}/reports"
    mkdir -p "$reports_dir"

    local md_file="${reports_dir}/summary.md"
    local html_file="${reports_dir}/summary.html"

    generate_markdown_report "$workspace" "$domain" "$md_file"
    generate_html_report "$workspace" "$domain" "$html_file"
}

# Generate an aggregated multi-target summary report
generate_multi_target_summary() {
    local output_base_dir="$1"
    shift
    local targets=("$@")

    local reports_dir="${output_base_dir}/reports"
    mkdir -p "$reports_dir"
    local summary_md="${reports_dir}/multi_target_summary.md"

    local scan_date
    scan_date="$(date +"%Y-%m-%d %H:%M:%S" 2>/dev/null || date)"

    {
        cat << EOF
# Multi-Target Reconnaissance Assessment Report

**Generated:** \`${scan_date}\`<br>
**Total Targets:** \`${#targets[@]}\`<br>
**Tool:** Recon Framework v${FRAMEWORK_VERSION}

---

## Target Summary Matrix

| Target Domain | Status | Subdomains | Resolved Hosts | Open Ports | Live URLs | Findings |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
EOF

        for target in "${targets[@]}"; do
            local ws="${output_base_dir}/${target}"
            local st="Unknown"
            if [[ -f "${ws}/manifest.json" ]]; then
                if grep -q '"status":[[:space:]]*"success"' "${ws}/manifest.json"; then
                    st="Success"
                elif grep -q '"status":[[:space:]]*"failed"' "${ws}/manifest.json"; then
                    st="Failed"
                fi
            fi

            local sub_c res_c port_c live_c find_c
            sub_c="$(_safe_line_count "${ws}/subdomains/all.txt")"
            res_c="$(_safe_line_count "${ws}/dns/resolved.txt")"
            port_c="$(_safe_line_count "${ws}/ports/naabu.txt")"
            live_c="$(_safe_line_count "${ws}/live/urls.txt")"
            find_c="$(_safe_line_count "${ws}/nuclei/findings.jsonl")"

            # shellcheck disable=SC2016
            printf '| **%s** | `%s` | %s | %s | %s | %s | %s |\n' \
                "$target" "$st" "$sub_c" "$res_c" "$port_c" "$live_c" "$find_c"
        done

        cat << EOF

---
*Notice: This report was generated for authorized security assessment purposes only.*
EOF
    } > "$summary_md"

    log_success "Multi-target summary report generated: $summary_md"
    return 0
}
