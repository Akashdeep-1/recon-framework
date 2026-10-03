# Phase 7: Dynamic DAG Orchestration Design

## Executive Summary

This document defines the architecture for Phase 7 of ReconForge: dynamic DAG-based orchestration with conditional and parallel stage execution. The design preserves all Phase 5.2/6 invariants while introducing graph-based execution control.

**Status**: Design only — no implementation.

---

## 1. Current Pipeline (Phase 6 Baseline)

```text
subdomains → dns → ports → live → crawling → vuln → reports
```

- Sequential by default, with `--stages` and `--skip` for selection
- `--resume` skips completed stages via manifest status
- Dependency validation: `dns` needs `subdomains`, `ports` needs `dns`, etc.

---

## 2. Target DAG Architecture

### Stage Definition Schema

Each stage defines:

```bash
# Stage descriptor (internal representation)
declare -A STAGE_DEFINITION=(
    [id]="subdomains"              # unique identifier
    [label]="Subdomain Discovery"  # human-readable
    [deps]="()"                    # array of stage IDs (empty = root)
    [inputs]="subdomains/all.txt"  # input artifact paths
    [outputs]="subdomains/all.txt subdomains/hosts.jsonl"  # output artifacts
    [cmd]="execute_subdomains_stage"  # plugin function
    [timeout]=300                  # seconds (0 = no timeout)
    [retries]=1                    # retry count
    [rate_limit]="subfinder"       # rate limit tool key
    [condition]="true"             # bash predicate for conditional execution
    [failure_policy]="FAIL_FAST"   # FAIL_FAST | CONTINUE | SKIP_DEPENDENTS | RETRY
    [parallel_group]="passive"     # stages in same group may run concurrently
)
```

### Canonical Stages

| Stage ID | Label | Deps | Inputs | Outputs | Cmd | Condition | Failure Policy | Parallel Group |
|----------|-------|------|--------|---------|-----|-----------|----------------|----------------|
| `subdomains` | Subdomain Discovery | `()` | target domain | `all.txt`, `hosts.jsonl` | `execute_subdomains_stage` | `true` | FAIL_FAST | `passive` |
| `dns` | DNS Resolution | `[subdomains]` | `subdomains/all.txt` | `resolved.txt`, `resolved.jsonl` | `run_dnsx` | `has_subdomains` | FAIL_FAST | - |
| `ports` | Port Discovery | `[dns]` | `dns/resolved.txt` | `ports.txt`, `ports.jsonl`, `web_candidates.txt` | `run_naabu` | `has_resolved_hosts` | FAIL_FAST | - |
| `live` | HTTP Probing | `[dns, ports]` | `dns/resolved.txt`, `ports/web_candidates.txt` | `httpx.txt`, `urls.txt` | `execute_live_stage` | `has_web_targets` | FAIL_FAST | - |
| `crawling` | URL Crawling | `[live]` | `live/urls.txt` | `katana.txt`, `urls.jsonl` | `run_katana` | `has_live_urls` | CONTINUE | - |
| `vuln` | Vulnerability Scan | `[crawling, live]` | `crawling/katana.txt`, `live/urls.txt` | `findings.jsonl`, `summary.json` | `run_nuclei` | `has_urls` | CONTINUE | - |
| `reports` | Report Generation | `[vuln]` | all outputs | `summary.md`, `summary.html` | `execute_reports_stage` | `true` | FAIL_FAST | - |

### Conditional Execution

```bash
# Stage condition predicates (evaluated at runtime)
has_subdomains() {
    [[ -s "${WORKSPACE}/subdomains/all.txt" ]] || is_stage_selected "subdomains"
}

has_resolved_hosts() {
    [[ -s "${WORKSPACE}/dns/resolved.txt" ]] || is_stage_selected "dns"
}

has_web_targets() {
    [[ -s "${WORKSPACE}/ports/web_candidates.txt" ]] || [[ -s "${WORKSPACE}/dns/resolved.txt" ]]
}

has_live_urls() {
    [[ -s "${WORKSPACE}/live/urls.txt" ]]
}

has_urls() {
    [[ -s "${WORKSPACE}/crawling/katana.txt" ]] || [[ -s "${WORKSPACE}/live/urls.txt" ]]
}
```

---

## 3. Dependency Model

### DAG Structure

```
subdomains (root)
    │
    ├─→ dns
    │      │
    │      └─→ ports
    │                │
    │                └─→ live
    │                      │
    │                      ├─→ crawling
    │                      │      │
    │                      │      └─→ vuln
    │                      │
    │                      └─→ vuln
    │
    └─→ (reports depends on vuln completion)
```

### Dependency Rules

1. **Explicit deps**: Stage waits for all dependencies to reach `success` or `resumed`
2. **Conditional deps**: If condition evaluates false, stage is `skipped` and dependents re-evaluate
3. **Artifact deps**: Stage can run if input artifact exists (supports `--resume`)
4. **No circular deps**: Validated at DAG load time

---

## 4. Parallel Execution Strategy

### Parallel Groups

```bash
declare -A PARALLEL_GROUPS=(
    [passive]="subdomains"           # subfinder + assetfinder already parallel
    [dns_resolve]="dns"              # single tool, no parallelism
    [port_scan]="ports"              # naabu handles internal concurrency
    [http_probe]="live"              # httpx handles internal concurrency
    [crawling]="crawling"            # katana handles internal concurrency
    [vuln_scan]="vuln"               # nuclei handles internal concurrency
    [reporting]="reports"            # report generation
)
```

### Safety Rules

1. **No shared-file writes**: Stages in same group must write to distinct output paths
2. **Rate-limit isolation**: Each stage acquires its own rate-limit token
3. **Workspace isolation**: Each target has isolated workspace; no cross-target parallelism in v1
4. **Manifest locking**: Stage status updates use atomic write (already in `manifest.sh`)
5. **Deterministic collection**: Results collected in dependency order after group completes

---

## 5. Failure Semantics

| Policy | Behavior | Use Case |
|--------|----------|----------|
| `FAIL_FAST` | Abort pipeline, mark stage `failed`, downstream `blocked` | Critical stages (subdomains, dns, ports, live, reports) |
| `CONTINUE` | Mark stage `failed`, downstream stages still evaluate conditions | Optional stages (crawling, vuln) |
| `SKIP_DEPENDENTS` | Mark stage `failed`, dependents marked `skipped` | When downstream absolutely requires this stage |
| `RETRY` | Handled by `run_pipeline_stage` retry loop (Phase 6) | All stages (configurable via `STAGE_RETRIES`) |

### Failure Propagation

```
Stage fails with FAIL_FAST
    ↓
Emit JSONL: stage_failed, dag_blocked
    ↓
Mark downstream stages BLOCKED
    ↓
Abort pipeline
    ↓
run_complete event with status=failed
```

---

## 6. Resume Semantics

### Invariant (Preserved from Phase 6)

```
completed stage + later failure
        ↓
resume
        ↓
completed stage is NOT re-executed
```

### DAG-Aware Resume Algorithm

```bash
resume_dag() {
    local target="$1"
    local workspace="$2"
    
    # 1. Load manifest
    local manifest="${workspace}/manifest.json"
    
    # 2. For each stage in topological order:
    for stage in "${DAG_ORDER[@]}"; do
        local status=$(get_manifest_stage_status "$manifest" "$stage")
        
        # 3. Skip if already success/resumed
        if [[ "$status" == "success" || "$status" == "resumed" ]]; then
            continue
        fi
        
        # 4. If blocked/failed, check if parent failed
        if [[ "$status" == "blocked" || "$status" == "failed" ]]; then
            local parent_failed=false
            for dep in "${DEPS[$stage]}"; do
                if [[ "$(get_manifest_stage_status "$manifest" "$dep")" == "failed" ]]; then
                    parent_failed=true
                    break
                fi
            done
            if [[ "$parent_failed" == true ]]; then
                # Parent failed — this stage stays blocked/skipped
                continue
            fi
        fi
        
        # 5. Otherwise, stage is ready to execute
        # Resume from here...
    done
}
```

### Manifest Status Transitions (Extended)

| From | To | Trigger |
|------|-----|---------|
| `pending` | `queued` | All deps satisfied, condition true |
| `pending` | `skipped` | Condition false, or in `--skip` |
| `pending` | `blocked` | Dependency failed (FAIL_FAST) |
| `queued` | `running` | Stage starts |
| `running` | `success` | Stage completes |
| `running` | `failed` | Stage exhausts retries |
| `running` | `retry` | Attempt fails, retries remain |
| `success` | `resumed` | `--resume` with valid output |
| `failed` | `blocked` | Downstream of failed stage |

---

## 7. Manifest Strategy

### Extended Manifest Format (Backward Compatible)

```json
{
  "target": "example.com",
  "start_time": "2026-10-03T12:00:00Z",
  "end_time": "2026-10-03T12:15:00Z",
  "status": "success",
  "config": { ... },
  "dag_version": 1,
  "stages": {
    "subdomains": {
      "status": "success",
      "duration_seconds": 10,
      "output_count": 50,
      "attempts": 1,
      "deps": [],
      "condition": true,
      "failure_policy": "FAIL_FAST",
      "parallel_group": "passive"
    },
    "dns": {
      "status": "success",
      "duration_seconds": 5,
      "output_count": 45,
      "attempts": 1,
      "deps": ["subdomains"],
      "condition": "has_subdomains",
      "failure_policy": "FAIL_FAST"
    },
    "ports": {
      "status": "success",
      "duration_seconds": 30,
      "output_count": 200,
      "attempts": 1,
      "deps": ["dns"],
      "condition": "has_resolved_hosts",
      "failure_policy": "FAIL_FAST"
    }
    ...
  }
}
```

### Migration Strategy

- Add `dag_version` field (default 0 = legacy linear)
- New fields (`deps`, `condition`, `failure_policy`, `parallel_group`) are optional
- `validate_pipeline_dependencies` continues to work for linear pipelines
- Phase 7 enables DAG when `dag_version >= 1`

---

## 8. JSONL Event Strategy

### New Events (Backward Compatible)

| Event | Fields |
|-------|--------|
| `dag_start` | `dag_version`, `stages`, `order` |
| `stage_queued` | `stage`, `deps_satisfied` |
| `stage_ready` | `stage`, `condition_evaluated` |
| `stage_skipped` | `stage`, `reason` |
| `stage_blocked` | `stage`, `blocked_by` |
| `stage_retry` | `stage`, `attempt`, `error` |
| `dag_blocked` | `blocked_stages`, `reason` |
| `dag_complete` | `status`, `completed_stages`, `failed_stages` |

### Existing Events Preserved

- `run_start`, `stage_start`, `tool_start`, `tool_complete`, `tool_error`
- `stage_complete`, `run_complete`, `finding`, `error`, `scope_rejection`

---

## 9. Acceptance Tests (Measurable)

| # | Test | Verification |
|---|------|--------------|
| 1 | Sequential DAG reproduces current pipeline | `recon.sh -d example.com` produces identical outputs/manifest to Phase 6 |
| 2 | Independent stages execute concurrently | Subfinder + Assetfinder run in parallel (verified by timestamps) |
| 3 | Conditional stages correctly skipped | `crawling` skipped when `live` has 0 results; `vuln` skipped when no URLs |
| 4 | Failed stages produce structured failure events | `stage_failed` + `dag_blocked` events in JSONL |
| 5 | Dependent stages blocked appropriately | `ports` blocked when `dns` fails with FAIL_FAST |
| 6 | Retry behavior deterministic | `STAGE_RETRIES=2` → exactly 3 attempts on transient failure |
| 7 | Resume does not re-run completed stages | `--resume` with valid manifest → stages show `resumed` |
| 8 | Manifest remains parseable | `jq` validation passes; Phase 6 manifest tests pass |
| 9 | Scope enforcement unchanged | Suffix-attack tests pass; `is_in_scope` unmodified |
| 10 | Rate limits enforced under parallel execution | Token bucket per tool; no stage exceeds configured RPS |
| 11 | JSONL event ordering understandable | Events correlatable by `run_id` + `stage` |
| 12 | Phase 5.2 tests pass | All 52 Phase 5.2 assertions pass |
| 13 | Phase 6 tests pass | All Phase 6 property/contract/chaos tests pass |

---

## 10. Implementation Scope (Phase 7 Only)

### In Scope
- DAG loader/validator in `lib/orchestration.sh`
- Topological sort for stage ordering
- Condition evaluator
- Parallel group executor
- Failure policy dispatcher
- Resume algorithm with DAG awareness
- Extended manifest with `dag_version`
- New JSONL events
- Unit tests for DAG logic

### Out of Scope (Later Phases)
- Asset database / history / correlation
- PostgreSQL / Redis / MLflow
- Cloud enumeration / API recon
- Distributed workers
- ML-based prioritization
- Live packet capture

---

## 11. Risk Assessment

| Risk | Mitigation |
|------|------------|
| Manifest format breaking changes | `dag_version` field; backward-compatible defaults |
| Race conditions in parallel groups | Distinct output paths; atomic manifest updates |
| Deadlock in dependency resolution | Topological sort with cycle detection |
| JSONL event ordering confusion | `run_id` + `stage` + `timestamp` correlation keys |
| Resume corruption | DAG-aware resume validates parent statuses |

---

## 12. Conclusion

This design extends ReconForge's orchestration from a fixed linear pipeline to a configurable DAG while strictly preserving Phase 5.2/6 invariants. The architecture is incremental: the existing sequential pipeline is a valid DAG subset, enabling safe evolution.