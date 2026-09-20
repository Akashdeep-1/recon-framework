# Changelog

All notable changes to this project will be documented in this file.

This project follows semantic versioning.

---

## [1.2.0] - 2026-09-20

### Security & Scope Safety (P0)
- Implemented canonical target normalization and strict scope enforcement (`is_in_scope`, `filter_in_scope`, `is_url_in_scope`, `filter_urls_in_scope`).
- Added defense against suffix collision attacks (`evil-target.com` vs `target.com`) and out-of-scope sibling domains.
- Applied scope validation before any active reconnaissance stage (DNSX, Naabu, HTTPX, Katana, Nuclei).

### Architecture & Pipeline
- Re-architected pipeline order: port discovery (`naabu`) executes prior to web crawling (`katana`) and vulnerability scanning (`nuclei`).
- Combined resolved domain hosts and discovered non-standard web ports into a unified target set for HTTP probing.
- Added parallel passive enumeration for Subfinder and Assetfinder (`lib/parallel.sh`).
- Added checkpoint and resumption mode (`-r`).
- Added automated Markdown and standalone HTML reporting (`lib/report.sh`).
- Implemented normalized JSONL data models for hosts, IPs, ports, and URLs (`lib/parser.sh`).

### Reliability & Quality
- Added `set -Eeuo pipefail` strict mode in orchestrator scripts with defensive subshell arithmetic.
- Fixed `BASH_SOURCE` path resolution in logger.
- Added dual logging: formatted console output and persistent `output/<domain>/logs/recon.log`.
- Updated `install.sh` to check only active pipeline dependencies and return non-zero exit codes on missing tools.
- Added zero-network automated unit and integration test suite with mock binaries.
- Configured ShellCheck (`.shellcheckrc`) and verified 100% clean static analysis.
- Implemented `Makefile` with `lint`, `test`, `check-deps`, and `clean` targets.

---

## [1.1.0] - 2026-06-28

### Added
- Initial project structure
- Configuration system
- Logger library
- Helper library
- Filesystem manager
- Dependency checker
- Main controller
- Workspace creation
- MIT License
