# Changelog

All notable changes to this project will be documented in this file.

This project follows semantic versioning.

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
