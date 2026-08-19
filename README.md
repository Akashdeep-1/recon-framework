# Recon Framework

A modular reconnaissance framework written in Bash for authorized security assessments, penetration testing, cybersecurity research, and educational purposes.

> ⚠️ **Disclaimer:** This project is intended only for systems and domains you own or have explicit authorization to assess. The author is not responsible for misuse.

---

## Features

- Modular Bash architecture
- Target domain validation
- Configuration management
- Colored logging
- Helper functions
- Dependency checking
- Automatic workspace creation
- Organized reconnaissance output
- Extensible plugin architecture
- Passive subdomain enumeration
- DNS resolution
- HTTP/HTTPS service detection
- Port discovery
- URL crawling
- Nuclei-based vulnerability detection
- Subdomain result merging and deduplication

---

## Reconnaissance Pipeline

                    Target Domain
                         │
                         ▼
                  Domain Validation
                         │
                         ▼
                  Workspace Creation
                         │
             ┌───────────┴───────────┐
             ▼                       ▼
        Subfinder                Assetfinder
             │                       │
             └───────────┬───────────┘
                         ▼
                  Subdomain Merge
                         │
                         ▼
                       DNSX
                         │
                         ▼
                  Resolved Hosts
                    /         \
                   /           \
                  ▼             ▼
               HTTPX          Naabu
                  │              │
                  ▼              ▼
             Live URLs       Open Ports
                  │
                  ▼
             URL Extraction
                  │
            ┌─────┴─────┐
            ▼           ▼
          Katana      Nuclei
            │           │
            ▼           ▼
      Discovered URLs  Security
                       Findings