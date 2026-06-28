# Recon Framework

A modular reconnaissance framework written in Bash for security assessments, penetration testing, and cybersecurity learning.

> ⚠️ This project is intended for authorized security testing and educational purposes only.

---

## Features

* Modular architecture
* Configuration management
* Colored logging
* Dependency checker
* Automatic workspace creation
* Organized output directories
* Extensible plugin system (coming soon)

---

## Project Structure

```
recon-framework/
├── config.sh
├── install.sh
├── recon.sh
├── lib/
├── plugins/
├── output/
├── reports/
├── logs/
└── README.md
```

---

## Current Status

Current Version: **v1.1.0**

Completed:

* Configuration system
* Logger
* Helper library
* Filesystem manager
* Dependency checker
* Main controller

---

## Planned Features

* Subfinder integration
* Assetfinder integration
* DNSX
* HTTPX
* Naabu
* Katana
* Nuclei
* HTML Reports
* Parallel execution

---

## Installation

```bash
git clone https://github.com/Akashdeep-1/recon-framework.git

cd recon-framework

chmod +x install.sh recon.sh

./install.sh
```

---

## Usage

```bash
./recon.sh -d example.com
```

---

## Output

```
output/
└── example.com/
    ├── subdomains/
    ├── dns/
    ├── live/
    ├── ports/
    ├── urls/
    ├── js/
    ├── nuclei/
    ├── screenshots/
    ├── reports/
    └── logs/
```

---

## Roadmap

### Version 1.2

* Plugin loader
* Subfinder plugin

### Version 1.3

* Assetfinder
* Merge results

### Version 1.4

* DNS resolution

### Version 2.0

* Full reconnaissance pipeline

---

## Author

Akashdeep Singh

---

## License

MIT License
