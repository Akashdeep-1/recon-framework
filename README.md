# Recon Framework

[![CI](https://github.com/Akashdeep-1/recon-framework/actions/workflows/ci.yml/badge.svg)](https://github.com/Akashdeep-1/recon-framework/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A modular, hardened reconnaissance framework written in Bash for authorized security assessments, penetration testing, cybersecurity research, and educational purposes.

> ⚠️ **Disclaimer & Authorization:** This project is intended strictly for systems and domains you own or have explicit written authorization to assess. The operator assumes full responsibility for compliance with all applicable laws and scope boundaries. The author is not responsible for misuse.

---

## Key Features

- **Strict Scope Enforcement:** Canonical target normalization and strict boundary enforcement preventing suffix-collision attacks (`evil-example.com` targeting `example.com`), out-of-scope sibling domains, and third-party CDNs.
- **Multi-Target Support:** Ingest single domains (`-d domain.com`), comma-separated lists (`-d d1,d2`), or target files (`-l targets.txt`) with strict per-target workspace and scope isolation.
- **Pipeline Orchestration:** Selectively execute or skip pipeline stages (`--stages subdomains,dns,live`, `--skip nuclei,ports`) with automated dependency validation.
- **Process Supervision:** Robust POSIX process-group supervision (`run_with_timeout`) with configurable stage timeouts, retries, and clean orphan-free process tree termination (exit code `124`).
- **Resumption Mode (`-r`):** Checkpoints completed stages to avoid repeating expensive reconnaissance workflows.
- **Normalized Data Models & JSON Schemas:** Validated Draft-07 JSON Schemas (`schemas/`) for hosts, resolved IPs, open ports, discovered URLs, and vulnerability findings.
- **Reporting & State Manifest:** Real-time run state tracking (`manifest.json`), automated executive Markdown reports, standalone HTML reports, and aggregated multi-target matrices.
- **Zero-Network Test Harness:** Comprehensive automated test suite (16 suites, unit + integration) executing deterministically offline with mock binaries.
- **Continuous Integration:** Automated GitHub Actions workflow validating syntax (`bash -n`), static analysis (`shellcheck`), formatting (`git diff --check`), and test passes on every push and pull request.

---

## Reconnaissance Pipeline

```text
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

# Quick Start

### 1. Verify Dependencies
Check required tools (`subfinder`, `assetfinder`, `dnsx`, `naabu`, `httpx`, `katana`, `nuclei`):
```bash
./install.sh --check
```
To view Go installation commands for any missing tools:
```bash
./install.sh --install-instructions
```

### 2. Basic Single-Domain Reconnaissance
```bash
./recon.sh -d example.com
```

### 3. Multi-Target Reconnaissance
```bash
# Comma-separated domains
./recon.sh -d example.com,target.org,api.example.com

# Target list file (one domain per line, supports # comments)
./recon.sh -l targets.txt
```

### 4. Resumption & Concurrency Tuning
```bash
# Resume an interrupted scan without repeating completed stages
./recon.sh -d example.com -r

# Custom output directory, concurrency, and rate limiting
./recon.sh -d example.com -o /custom/workspace -t 25 --rate-limit 100
```

### 5. Selective Stage Execution
```bash
# Run only passive enumeration and DNS resolution
./recon.sh -d example.com --stages subdomains,dns

# Skip port scanning and vulnerability scanning
./recon.sh -d example.com --skip ports,nuclei
```

---

## Docker Containerization

The framework provides a production-grade multi-stage Docker build producing a minimal, non-root, reproducible container (`alpine:3.20`) with all reconnaissance tools compiled from pinned versions.

### Build the Image
```bash
docker build -t recon-framework:latest .
```

### Run Reconnaissance via Docker
```bash
# Mount host output directory for persistence
docker run --rm -v $(pwd)/output:/app/output recon-framework:latest -d example.com

# Multi-target reconnaissance with custom concurrency
docker run --rm -v $(pwd)/output:/app/output recon-framework:latest -d example.com,target.org -t 25

# Target list file execution
docker run --rm -v $(pwd)/output:/app/output -v $(pwd)/targets.txt:/app/targets.txt:ro \
  recon-framework:latest -l /app/targets.txt
```

### Run via Docker Compose
```bash
# Start container assessment using docker-compose
docker compose run --rm recon -d example.com
```

### Container Security & Architecture
- **Non-Root Execution:** Runs under dedicated unprivileged service account `recon` (`UID 10001:GID 10001`).
- **Minimal Attack Surface:** Multi-stage build discards Go compilers, retaining only runtime binaries and libraries.
- **Rootless Network Capabilities:** Linux capabilities (`cap_net_raw,cap_net_bind_service`) applied to Naabu binary for raw packet capture without requiring root privileges.

---

## CLI Reference

```text
Usage:
  ./recon.sh -d <domain.com> [options]
  ./recon.sh -d <domain1,domain2,...> [options]
  ./recon.sh -l <targets.txt> [options]

Core Options:
  -d, --domain <domain(s)>    Target domain(s), single or comma-separated
  -l, --list <file>           File containing target domains (one per line)
  -o, --output <directory>    Custom output workspace directory
  -r, --resume                Resume mode (skip stages with existing valid output)
  -v, --verbose               Enable verbose console debugging output
  -h, --help                  Display help message

Pipeline Orchestration:
  --stages <s1,s2,...>        Comma-separated stages to run (default: all)
                              Available: subdomains, dns, ports, live, crawling, vuln, reports
  --skip <s1,s2,...>          Comma-separated stages to skip

Execution Control:
  -t, --threads <n>           Concurrency threads for tools (default: 50)
  --rate-limit <n>            Maximum requests per second (default: 150)
  --timeout <seconds>         Stage execution timeout (default: 300)
  --retries <count>           Max retry attempts on stage failure (default: 1)
```

---

## Workspace Structure

Each assessment produces an isolated workspace per target under `output/<target-domain>/`:

```text
output/
├── <target-domain>/
│   ├── manifest.json         # State tracking, timings, and metrics
│   ├── subdomains/
│   │   ├── subfinder.txt     # Subfinder passive discoveries
│   │   ├── assetfinder.txt   # Assetfinder passive discoveries
│   │   ├── all.txt           # Merged, scoped, deduplicated hostnames
│   │   └── hosts.jsonl       # Machine-readable host records
│   ├── dns/
│   │   ├── resolved.txt      # Live hostnames confirmed via DNSX
│   │   └── resolved.jsonl    # Host-to-IP resolution records
│   ├── ports/
│   │   ├── naabu.txt         # Open ports (host:port)
│   │   ├── ports.jsonl       # Structured port records
│   │   └── web_candidates.txt # Identified candidate HTTP service ports
│   ├── live/
│   │   ├── targets.txt       # Combined DNS + Naabu HTTP probe endpoints
│   │   ├── httpx.txt         # Raw HTTP probing responses
│   │   └── urls.txt          # In-scope live HTTP/HTTPS endpoints
│   ├── urls/
│   │   ├── katana.txt        # Discovered endpoints via crawler
│   │   └── urls.jsonl        # Normalized URL records
│   ├── nuclei/
│   │   ├── findings.jsonl    # Vulnerability scan findings
│   │   └── summary.json      # Severity breakdown metrics
│   ├── reports/
│   │   ├── summary.md        # Markdown assessment report
│   │   └── summary.html      # Standalone HTML assessment report
│   └── logs/
│       └── recon.log         # Persistent timestamped execution log
└── reports/
    └── multi_target_summary.md # Aggregated multi-target matrix (when > 1 target)
```

---

## Data Models & JSON Schemas

The framework specifies formal [JSON Schema Draft-07](schemas/) definitions for machine readability and SIEM/pipeline integration:

- **Host Model:** [`schemas/host.schema.json`](schemas/host.schema.json)
- **Port Model:** [`schemas/port.schema.json`](schemas/port.schema.json)
- **URL Model:** [`schemas/url.schema.json`](schemas/url.schema.json)
- **Finding Model:** [`schemas/finding.schema.json`](schemas/finding.schema.json)

For detailed entity relationships and examples, see [Data Models Documentation](docs/data-models.md).

---

## Testing & Quality Assurance

### Run Test Suite
```bash
make test
# or:
bash tests/run_tests.sh
```

### Run Static Analysis & Linter
```bash
make lint
# or:
bash -n recon.sh config.sh install.sh lib/*.sh tests/**/*.sh
shellcheck recon.sh config.sh install.sh lib/*.sh tests/**/*.sh
git diff --check
```

---

## Release Procedure

The framework uses semantic versioning with a single canonical source of truth in `VERSION`. For the step-by-step release checklist, see [Release Procedure](docs/release-procedure.md).

---

## Supported Platforms

The framework is architected for cross-platform portability across modern POSIX environments:

- **Docker:** Fully supported via official multi-stage container (recommended for production).
- **Linux:** Native support on Ubuntu, Debian, Kali Linux, Arch, Fedora.
- **macOS:** Supported with GNU coreutils and bash (`brew install bash coreutils jq`).
- **Windows:** Supported via Git Bash and WSL2 (Windows Subsystem for Linux).

---

## Limitations & Operational Boundaries

- **Zero-Network Testing:** The integrated test harness uses deterministic mock binaries and performs no live network activity.
- **Scope Authority:** The framework automatically filters third-party CDN domains and sibling domains; wildcards (`*.example.com`) are expanded only via active/passive discoveries.
- **Active Scans:** Vulnerability scanning (`nuclei`) and crawling (`katana`) require explicit authorization from the target domain owner.

---

## License

This project is licensed under the [MIT License](LICENSE).