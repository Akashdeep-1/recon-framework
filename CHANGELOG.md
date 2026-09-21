# Changelog

All notable changes to this project will be documented in this file.

This project follows semantic versioning.

---

## [1.3.0] - 2026-09-21

### Production Hardening, Reliability & Containerization (Phase 4)
- **Manifest JSON Hardening & Atomic Integrity:** Multi-engine JSON processing supporting `jq` with deterministic Python standard-library fallback. Atomic temporary-file swapping prevents partial, truncated, or corrupt manifest writes. Added `get_manifest_stage_status` and `get_manifest_overall_status` inspection helpers.
- **Docker Multi-Stage Containerization:** Added production multi-stage `Dockerfile` compiling pinned Go tools (`subfinder` v2.6.8, `assetfinder` v0.1.1, `dnsx` v1.2.1, `naabu` v2.3.1, `httpx` v1.6.8, `katana` v1.1.0, `nuclei` v3.3.2) on Alpine Linux 3.20. Configured rootless service execution (`UID 10001:GID 10001`), Linux network packet capture capabilities, `.dockerignore`, and `docker-compose.yml`.
- **CI Container Testing:** Integrated automated Docker image build, help display, non-root user verification, and PATH tool discovery into `.github/workflows/ci.yml`.
- **Process & Resource Hardening:** Eliminated orphan `sleep` processes from timeout watcher subshells using signal trapping on watcher completion. Hardened process-group signalling across Unix environments.
- **Pipeline Reliability & Crash Recovery:** Interrupted or failed stages are verified via previous manifest state and re-executed upon resumption (`-r`) rather than prematurely skipped. Structural artifact validation ensures corrupted or 0-byte files trigger fresh stage runs.
- **Security & Scope Hardening:** Enhanced scope enforcement and URL authority parsing to neutralize userinfo credential confusion tricks (`http://target@attacker.com`). Strict positive integer boundary validation for CLI concurrency, timeout, rate-limit, and retries.
- **Test Harness Expansion:** Added dedicated manifest hardening unit tests (`tests/unit/test_manifest_hardening.sh`), crash recovery integration tests (`tests/integration/test_crash_recovery.sh`), and security boundary integration tests (`tests/integration/test_security_boundaries.sh`), expanding test suite to 19 suites (270+ assertions).

---

## [1.2.0] - 2026-09-20

### Engineering Maturity & Multi-Target (Phase 3)
- **Multi-Target Ingestion & Scope Isolation:** Support for comma-separated targets (`-d d1,d2`) and target list files (`-l targets.txt`) with strict per-target scope enforcement, independent workspaces, separate logs/manifests, and aggregated reporting matrix (`output/reports/multi_target_summary.md`).
- **Continuous Integration:** Added GitHub Actions workflow (`.github/workflows/ci.yml`) validating syntax (`bash -n`), static analysis (`shellcheck`), formatting (`git diff --check`), and automated tests on `main` branch pushes and PRs.
- **Canonical Versioning:** Established single source of truth in root `VERSION` file, integrated with `config.sh` and CLI banner, with documented release procedure (`docs/release-procedure.md`).
- **Data Modeling & JSON Schemas:** Published Draft-07 JSON Schemas for `HostRecord`, `PortRecord`, `URLRecord`, and `FindingRecord` in `schemas/`, with comprehensive architectural documentation in `docs/data-models.md`.
- **Testing Expansion:** Added multi-target CLI parsing unit tests (`tests/unit/test_multi_target_cli.sh`) and cross-target scope isolation integration tests (`tests/integration/test_multi_target_isolation.sh`), expanding test harness to 16 suites.

### Pipeline Orchestration & Supervision (Phase 2)
- **Stage Selection & Exclusion:** Granular execution control via `--stages <list>` and `--skip <list>` with alias normalization and upstream dependency enforcement.
- **Process Group Supervision:** POSIX process-group supervision (`run_with_timeout`) with graceful SIGTERM and SIGKILL escalation, watcher process reaping, and exit code `124`.
- **Pipeline Manifest:** Real-time state tracking in `manifest.json` recording stage durations, attempts, and record counts across six lifecycle states (`pending`, `running`, `success`, `skipped`, `resumed`, `failed`).
- **HTTPX & Naabu Integration:** Unified port discovery into live HTTP candidate target extraction.
- **Configurable Controls:** Added CLI overrides for custom output directory (`-o`), concurrency (`-t`), rate limiting (`--rate-limit`), timeouts (`--timeout`), and retries (`--retries`).

### Security & Scope Safety (Phase 1)
- **Scope Enforcement:** Canonical domain normalization and strict suffix-attack prevention (`is_in_scope`, `filter_in_scope`, `is_url_in_scope`, `filter_urls_in_scope`).
- **Pipeline Reordering:** Port discovery (`naabu`) executed prior to web crawling (`katana`) and vulnerability scanning (`nuclei`).
- **Reporting:** Automatic generation of Markdown and standalone HTML assessment reports (`lib/report.sh`).
- **Zero-Network Test Harness:** Automated test runner with deterministic mock tool binaries.

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
