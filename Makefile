# ============================================
# Recon Framework - Makefile
# ============================================

.PHONY: all lint test check-deps clean help

SHELL := /usr/bin/env bash

all: lint test

help:
	@echo "Available targets:"
	@echo "  make lint        - Run ShellCheck and bash syntax checks"
	@echo "  make test        - Run automated unit and integration tests"
	@echo "  make check-deps  - Check required reconnaissance dependencies"
	@echo "  make clean       - Remove temporary files and cached test outputs"

lint:
	@echo "=== Checking Bash syntax ==="
	@bash -n recon.sh config.sh install.sh lib/*.sh
	@echo "=== Running ShellCheck ==="
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck recon.sh config.sh install.sh lib/*.sh; \
	elif [ -x "$$(command -v python 2>/dev/null)" ] && python -c "import shellcheck" 2>/dev/null; then \
		python -m shellcheck recon.sh config.sh install.sh lib/*.sh; \
	else \
		echo "Notice: shellcheck binary not found in PATH, checking standard script syntax."; \
	fi
	@echo "Lint checks passed."

test:
	@echo "=== Running Test Suite ==="
	@bash tests/run_tests.sh

check-deps:
	@bash install.sh --check

clean:
	@echo "Cleaning temporary test files..."
	@rm -rf /tmp/recon_* tests/fixtures/output* output/mock* output/test* 2>/dev/null || true
	@echo "Clean completed."
