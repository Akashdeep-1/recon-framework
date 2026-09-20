# Canonical Data Models & Schemas

The Recon Framework produces structured, machine-readable JSONL (JSON Lines) and JSON artifacts across each pipeline stage. This document specifies the entity models, relational hierarchy, and corresponding JSON Schemas.

---

## Entity Hierarchy

The framework models reconnaissance data across six core entities:

```
Target (Root Assessment Domain)
  │
  ├── Host (Discovered Subdomain / FQDN)
  │     │
  │     ├── IP (Resolved Network Layer Addresses)
  │     │
  │     └── Port / Service (Open Ports & Transport Protocols)
  │
  └── URL (Probed & Crawled Application Endpoints)
        │
        └── Finding (Security Vulnerabilities & Misconfigurations)
```

---

## JSONL Model Specifications

### 1. Host Record (`hosts.jsonl`, `resolved.jsonl`)
- **Schema:** [`schemas/host.schema.json`](../schemas/host.schema.json)
- **Path:** `output/<domain>/subdomains/hosts.jsonl`, `output/<domain>/dns/resolved.jsonl`
- **Example:**
  ```json
  {"host":"api.example.com","target":"example.com","source":"subdomain"}
  {"host":"api.example.com","ip":"192.0.2.1","target":"example.com"}
  ```

### 2. Port Record (`ports.jsonl`)
- **Schema:** [`schemas/port.schema.json`](../schemas/port.schema.json)
- **Path:** `output/<domain>/ports/ports.jsonl`
- **Example:**
  ```json
  {"host":"api.example.com","port":443,"protocol":"tcp","target":"example.com"}
  ```

### 3. URL Record (`urls.jsonl`)
- **Schema:** [`schemas/url.schema.json`](../schemas/url.schema.json)
- **Path:** `output/<domain>/urls/urls.jsonl`
- **Example:**
  ```json
  {"url":"https://api.example.com/v1/health","host":"api.example.com","target":"example.com","source":"katana"}
  ```

### 4. Vulnerability Findings (`findings.jsonl`, `summary.json`)
- **Schema:** [`schemas/finding.schema.json`](../schemas/finding.schema.json)
- **Path:** `output/<domain>/nuclei/findings.jsonl`, `output/<domain>/nuclei/summary.json`
- **Summary Example:**
  ```json
  {
    "target": "example.com",
    "total_findings": 3,
    "severity_breakdown": {
      "critical": 1,
      "high": 1,
      "medium": 1,
      "low": 0,
      "info": 0
    }
  }
  ```

### 5. Pipeline Run Manifest (`manifest.json`)
- **Path:** `output/<domain>/manifest.json`
- **Lifecycle States:** `pending` -> `running` -> `success` / `failed` / `skipped` / `resumed`
- **Metrics Tracked:** Execution start/end times, durations (seconds), output record counts, retry attempts.
