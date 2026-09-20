# Release Procedure

This document defines the formal release workflow for the Recon Framework.

---

## Semantic Versioning

The Recon Framework adheres to [Semantic Versioning 2.0.0](https://semver.org/):
- **MAJOR (`X.0.0`)**: Incompatible API or CLI architectural breaks, major pipeline redesigns.
- **MINOR (`0.Y.0`)**: Backwards-compatible feature additions, new tool integrations, stage flags.
- **PATCH (`0.0.Z`)**: Backwards-compatible bug fixes, security hardenings, parser patches.

---

## Canonical Version Source

The single source of truth for the framework version is the root file:
```
VERSION
```
All framework components (`config.sh`, `recon.sh`, `lib/cli.sh`, `lib/report.sh`) derive their version directly from this file.

---

## Release Checklist

Follow these steps in sequence when publishing a new release:

### 1. Update Version
Bump the semantic version in the canonical `VERSION` file:
```bash
echo "1.3.0" > VERSION
```

### 2. Update Changelog
Add a new release section to `CHANGELOG.md` following [Keep a Changelog](https://keepachangelog.com/):
- Document new features, bug fixes, security enhancements, and breaking changes.
- Record the release date (`YYYY-MM-DD`).

### 3. Run Static Analysis & Linter
Verify code style and syntax across all shell scripts:
```bash
bash -n recon.sh config.sh install.sh lib/*.sh tests/**/*.sh tests/*.sh
shellcheck recon.sh config.sh install.sh lib/*.sh tests/**/*.sh tests/*.sh
git diff --check
```

### 4. Run Automated Test Suite
Execute the full zero-network regression test suite:
```bash
make test
# or:
bash tests/run_tests.sh
```
Ensure all test suites pass with 0 failures before proceeding.

### 5. Commit Release Changes
Stage the updated `VERSION` and `CHANGELOG.md`:
```bash
git add VERSION CHANGELOG.md config.sh
git commit -m "chore(release): bump version to v1.3.0"
```

### 6. Create Git Tag
Tag the commit with an annotated semantic tag:
```bash
git tag -a v1.3.0 -m "Release v1.3.0"
```

### 7. Push to Remote & Publish
Push the commit and tag to GitHub:
```bash
git push origin main --tags
```
Verify the GitHub Actions CI workflow runs and passes on the tagged commit.
Create a GitHub Release referencing the new tag and paste the changelog section.
