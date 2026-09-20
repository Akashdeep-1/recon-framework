# Recon Framework

A modular reconnaissance framework written in Bash for authorized security assessments, penetration testing, cybersecurity research, and educational purposes.

> ⚠️ **Disclaimer & Authorization:** This project is intended strictly for systems and domains you own or have explicit written authorization to assess. The operator assumes full responsibility for compliance with all applicable laws and scope boundaries. The author is not responsible for misuse.

---

## Features

- **Strict Scope Enforcement:** Canonical target normalization and suffix-attack prevention (rejects sibling domains like `evil-example.com`, third-party CDNs, and out-of-scope hosts).
- **Hardened Pipeline Architecture:** Parallel passive enumeration, DNS resolution, port scanning before web crawling, HTTP probing, URL crawling, and safe vulnerability scanning.
- **Normalized Data Models:** Structured JSONL artifacts for hosts, IPs, ports, services, URLs, and vulnerability findings without heavy database dependencies.
- **Resumption Mode (`-r`):** Checkpoints completed stages to avoid repeating time-consuming scans.
- **Configurable Safety Profiles:** Tunable rate limits, timeouts, concurrency bounds, and severity filters for Nuclei and HTTPX.
- **Reporting:** Automatic generation of executive Markdown and standalone HTML reports.
- **Persistent Logging:** Formatted console output with clean, timestamped plain-text logs in `output/<domain>/logs/recon.log`.
- **Zero-Network Test Suite:** Comprehensive automated unit and integration tests using mock binaries.

---

## Reconnaissance Pipeline

```
Subfinder ──┐
            ├──> Merge & Scope ──> DNSX ──┬──> HTTPX ──┐
Assetfinder ┘                             │            │
                                          └──> Naabu ──┤
                                                       ↓
                                                    Targets
                                                       ↓
                                                    Katana
                                                       ↓
                                                    Nuclei
                                                       ↓
                                                    Reports
```

---

## Quick Start

### 1. Verify Dependencies
Check required tools (`subfinder`, `assetfinder`, `dnsx`, `naabu`, `httpx`, `katana`, `nuclei`):
```bash
./install.sh --check
```
To view Go installation commands for any missing tools:
```bash
./install.sh --install-instructions
```

### 2. Run Reconnaissance
```bash
# Basic run
./recon.sh -d example.com

# Resume an interrupted assessment
./recon.sh -d example.com -r
```

### 3. Run Automated Tests
```bash
make test
# or:
bash tests/run_tests.sh
```

### 4. Run Linter & Static Analysis
```bash
make lint
```

---

## Workspace Structure

Each assessment produces an organized workspace under `output/<target-domain>/`:
```
output/<domain>/
├── subdomains/
│   ├── subfinder.txt
│   ├── assetfinder.txt
│   ├── all.txt          # In-scope deduplicated domains
│   └── hosts.jsonl      # Normalized host models
├── dns/
│   ├── resolved.txt     # DNS-resolved hosts
│   └── resolved.jsonl   # Host-to-IP mappings
├── ports/
│   ├── naabu.txt        # Open ports (host:port)
│   ├── ports.jsonl      # Normalized port records
│   └── web_candidates.txt # Discovered web service ports
├── live/
│   ├── targets.txt      # Combined DNS + Naabu web endpoints
│   ├── httpx.txt        # Detailed HTTP probing output
│   └── urls.txt         # Clean live in-scope URLs
├── urls/
│   ├── katana.txt       # Crawled application URLs
│   └── urls.jsonl       # Normalized URL models
├── nuclei/
│   ├── findings.jsonl   # Vulnerability scan findings
│   └── summary.json     # Severity metrics breakdown
├── reports/
│   ├── summary.md       # Markdown assessment report
│   └── summary.html     # Standalone HTML assessment report
└── logs/
    └── recon.log        # Persistent timestamped execution log
```