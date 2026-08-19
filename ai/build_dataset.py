#!/usr/bin/env python3

"""
Recon Framework - Dataset Builder

Converts reconnaissance feature JSON files into a tabular CSV dataset.

Usage:
    python3 ai/build_dataset.py

Output:
    ai/dataset.csv
"""

import csv
import json
from pathlib import Path


# --------------------------------------------------
# Project Paths
# --------------------------------------------------

BASE_DIR = Path(__file__).resolve().parent.parent
OUTPUT_DIR = BASE_DIR / "output"
DATASET_DIR = BASE_DIR / "ai"
DATASET_FILE = DATASET_DIR / "dataset.csv"


# --------------------------------------------------
# ML Feature Columns
# --------------------------------------------------

FEATURE_COLUMNS = [
    "target",

    # Subdomains
    "subfinder_count",
    "assetfinder_count",
    "subdomain_count",

    # DNS
    "resolved_host_count",

    # HTTP
    "live_http_count",
    "technology_count",
    "server_count",

    # URLs
    "live_url_count",
    "katana_url_count",
    "javascript_url_count",
    "api_url_count",

    # Ports
    "open_port_count",
    "unique_port_count",

    # Nuclei
    "nuclei_total",
    "nuclei_critical",
    "nuclei_high",
    "nuclei_medium",
    "nuclei_low",
    "nuclei_info",
]


# --------------------------------------------------
# Find Feature Files
# --------------------------------------------------

def find_feature_files():
    """Find all generated features.json files."""

    if not OUTPUT_DIR.exists():
        return []

    return sorted(
        OUTPUT_DIR.glob("*/ai/features.json")
    )


# --------------------------------------------------
# Load Feature File
# --------------------------------------------------

def load_features(path):
    """Load one JSON feature file."""

    try:
        with path.open(
            "r",
            encoding="utf-8"
        ) as file:

            data = json.load(file)

        if not isinstance(data, dict):
            print(f"[WARNING] Invalid feature format: {path}")
            return None

        return data

    except json.JSONDecodeError:
        print(f"[WARNING] Invalid JSON: {path}")
        return None

    except OSError as error:
        print(f"[WARNING] Could not read {path}: {error}")
        return None


# --------------------------------------------------
# Normalize Feature Row
# --------------------------------------------------

def normalize_features(data):
    """
    Convert a feature dictionary into a fixed
    tabular representation.
    """

    row = {}

    for column in FEATURE_COLUMNS:

        value = data.get(column, 0)

        # Target remains text.
        if column == "target":
            row[column] = value
            continue

        # Dictionaries/lists are not directly useful
        # in the CSV feature table.
        if isinstance(value, (dict, list)):
            row[column] = 0
            continue

        # Convert numeric values to integers where possible.
        try:
            row[column] = int(value)

        except (TypeError, ValueError):
            row[column] = 0

    return row


# --------------------------------------------------
# Build Dataset
# --------------------------------------------------

def build_dataset():

    feature_files = find_feature_files()

    if not feature_files:
        print(
            "[ERROR] No features.json files found."
        )

        print(
            "Run extract_features.py first."
        )

        return False

    rows = []

    for feature_file in feature_files:

        print(
            f"[INFO] Loading: {feature_file}"
        )

        data = load_features(feature_file)

        if data is None:
            continue

        row = normalize_features(data)

        rows.append(row)

    if not rows:

        print(
            "[ERROR] No valid feature records found."
        )

        return False

    DATASET_DIR.mkdir(
        parents=True,
        exist_ok=True
    )

    try:

        with DATASET_FILE.open(
            "w",
            newline="",
            encoding="utf-8"
        ) as file:

            writer = csv.DictWriter(
                file,
                fieldnames=FEATURE_COLUMNS
            )

            writer.writeheader()
            writer.writerows(rows)

    except OSError as error:

        print(
            f"[ERROR] Could not create dataset: {error}"
        )

        return False

    print()
    print(
        f"[SUCCESS] Dataset created: {DATASET_FILE}"
    )

    print(
        f"[INFO] Records: {len(rows)}"
    )

    print(
        f"[INFO] Features: {len(FEATURE_COLUMNS) - 1}"
    )

    return True


# --------------------------------------------------
# Main
# --------------------------------------------------

def main():

    success = build_dataset()

    if not success:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
