#!/usr/bin/env python3
"""
Contract tests for ReconForge tool output parsing.
Tests that tool output is correctly parsed and validated.
"""

import sys
import os
import subprocess
import json
import tempfile
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent.parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

def run_bash_parser(parser_func, *args):
    """Run a parser function from lib/parser.sh"""
    script = f"""
source "{PROJECT_ROOT}/lib/parser.sh"
{parser_func} {" ".join(f'"{arg}"' for arg in args)}
"""
    result = subprocess.run(
        ["bash", "-c", script],
        capture_output=True,
        text=True,
        cwd=PROJECT_ROOT
    )
    return result.returncode, result.stdout, result.stderr

def test_dnsx_parser():
    """Test DNSx output parsing"""
    # Valid dnsx output (matches mock format: host [ip])
    valid_output = """example.com [93.184.216.34]
api.example.com [93.184.216.34]
www.example.com [93.184.216.34]"""

    with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False) as f:
        f.write(valid_output)
        input_file = f.name

    with tempfile.NamedTemporaryFile(mode='w', suffix='.jsonl', delete=False) as f:
        output_file = f.name

    try:
        code, out, err = run_bash_parser("parse_dnsx_output", input_file, output_file, "example.com")
        assert code == 0, f"parse_dnsx_output failed: {err}"

        # Read the output file
        with open(output_file) as f:
            lines = f.read().strip().split('\n')

        for line in lines:
            if line:
                data = json.loads(line)
                assert "host" in data
                assert "ip" in data
                assert "target" in data
                # Accept both target domain and subdomains
                assert data["host"] == "example.com" or data["host"].endswith(".example.com")

        # Empty output
        with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False) as f:
            empty_input = f.name
        with tempfile.NamedTemporaryFile(mode='w', suffix='.jsonl', delete=False) as f:
            empty_output = f.name

        code, out, err = run_bash_parser("parse_dnsx_output", empty_input, empty_output, "example.com")
        assert code == 0

        # Malformed output
        with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False) as f:
            f.write("not a valid line")
            bad_input = f.name
        with tempfile.NamedTemporaryFile(mode='w', suffix='.jsonl', delete=False) as f:
            bad_output = f.name

        code, out, err = run_bash_parser("parse_dnsx_output", bad_input, bad_output, "example.com")
        assert code == 0  # Should not crash

    finally:
        for fname in [input_file, output_file]:
            if os.path.exists(fname):
                os.unlink(fname)

    print("✓ DNSx parser contract tests passed")

def test_naabu_parser():
    """Test Naabu output parsing"""
    valid_output = """example.com:80
example.com:443
api.example.com:8080
api.example.com:8443"""

    with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False) as f:
        f.write(valid_output)
        input_file = f.name

    with tempfile.NamedTemporaryFile(mode='w', suffix='.jsonl', delete=False) as f:
        output_file = f.name

    try:
        code, out, err = run_bash_parser("parse_naabu_output", input_file, output_file, "example.com")
        assert code == 0, f"parse_naabu_output failed: {err}"

        with open(output_file) as f:
            lines = f.read().strip().split('\n')

        for line in lines:
            if line:
                data = json.loads(line)
                assert "host" in data
                assert "port" in data
                assert isinstance(data["port"], int)
                assert 1 <= data["port"] <= 65535
                assert data["protocol"] == "tcp"
                assert data["target"] == "example.com"

        # Empty output
        with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False) as f:
            empty_input = f.name
        with tempfile.NamedTemporaryFile(mode='w', suffix='.jsonl', delete=False) as f:
            empty_output = f.name

        code, out, err = run_bash_parser("parse_naabu_output", empty_input, empty_output, "example.com")
        assert code == 0

    finally:
        for fname in [input_file, output_file]:
            if os.path.exists(fname):
                os.unlink(fname)

    print("✓ Naabu parser contract tests passed")

def test_nuclei_parser():
    """Test Nuclei JSONL output parsing"""
    valid_output = """{"template":"cve-2021-44228","severity":"critical","host":"example.com","matched":"example.com","description":"Log4j RCE","type":"http"}"""

    with tempfile.NamedTemporaryFile(mode='w', suffix='.jsonl', delete=False) as f:
        f.write(valid_output + '\n')
        input_file = f.name

    with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
        summary_file = f.name

    try:
        code, out, err = run_bash_parser("parse_nuclei_findings", input_file, summary_file, "example.com")
        assert code == 0, f"parse_nuclei_findings failed: {err}"

        with open(summary_file) as f:
            summary = json.load(f)

        assert "target" in summary
        assert "total_findings" in summary
        assert "severity_breakdown" in summary
        assert summary["total_findings"] == 1
        assert summary["severity_breakdown"]["critical"] == 1

        # Empty output
        with tempfile.NamedTemporaryFile(mode='w', suffix='.jsonl', delete=False) as f:
            empty_input = f.name
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            empty_summary = f.name

        code, out, err = run_bash_parser("parse_nuclei_findings", empty_input, empty_summary, "example.com")
        assert code == 0

        with open(empty_summary) as f:
            empty_summary_data = json.load(f)
        assert empty_summary_data["total_findings"] == 0

        # Malformed JSON
        with tempfile.NamedTemporaryFile(mode='w', suffix='.jsonl', delete=False) as f:
            f.write("not valid json\n")
            bad_input = f.name
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            bad_summary = f.name

        code, out, err = run_bash_parser("parse_nuclei_findings", bad_input, bad_summary, "example.com")
        assert code == 0

    finally:
        for fname in [input_file, summary_file]:
            if os.path.exists(fname):
                os.unlink(fname)

    print("✓ Nuclei parser contract tests passed")

def test_hosts_jsonl_parser():
    """Test hosts JSONL generation"""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False) as f:
        f.write("sub.example.com\napi.example.com\ndev.example.com\n")
        input_file = f.name

    with tempfile.NamedTemporaryFile(mode='w', suffix='.jsonl', delete=False) as f:
        output_file = f.name

    try:
        code, out, err = run_bash_parser("parse_hosts_jsonl", input_file, output_file, "example.com")
        assert code == 0, f"parse_hosts_jsonl failed: {err}"

        with open(output_file) as f:
            lines = f.read().strip().split('\n')

        for line in lines:
            if line:
                data = json.loads(line)
                assert "host" in data
                assert "target" in data
                assert "source" in data
                assert data["source"] == "subdomain"
                assert data["host"].endswith(".example.com")

        # Empty input
        with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False) as f:
            empty_input = f.name
        with tempfile.NamedTemporaryFile(mode='w', suffix='.jsonl', delete=False) as f:
            empty_output = f.name

        code, out, err = run_bash_parser("parse_hosts_jsonl", empty_input, empty_output, "example.com")
        assert code == 0

    finally:
        for fname in [input_file, output_file]:
            if os.path.exists(fname):
                os.unlink(fname)

    print("✓ Hosts JSONL parser contract tests passed")

def test_web_ports_extraction():
    """Test web ports extraction from naabu output"""
    naabu_output = """example.com:80
example.com:443
example.com:22
example.com:8080
example.com:8443
evil-target.com:80"""

    with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False) as f:
        f.write(naabu_output)
        input_file = f.name

    with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False) as f:
        output_file = f.name

    try:
        code, out, err = run_bash_parser("extract_web_ports_from_naabu", input_file, output_file, "example.com")
        assert code == 0, f"extract_web_ports_from_naabu failed: {err}"

        with open(output_file) as f:
            lines = f.read().strip().split('\n')

        ports_found = set()
        for line in lines:
            if line:
                if ':' in line:
                    host, port = line.rsplit(':', 1)
                else:
                    host, port = line, '80' if line else '443'
                ports_found.add((host, port))

        # Should include standard web ports (80, 443) and non-standard (8080, 8443)
        assert ("example.com", "80") in ports_found or ("example.com", "443") in ports_found
        assert ("example.com", "8080") in ports_found
        assert ("example.com", "8443") in ports_found
        # Should NOT include SSH (22) or out-of-scope (evil-target.com)
        assert ("example.com", "22") not in ports_found
        assert ("evil-target.com", "80") not in ports_found

    finally:
        for fname in [input_file, output_file]:
            if os.path.exists(fname):
                os.unlink(fname)

    print("✓ Web ports extraction contract tests passed")

def test_katana_parser():
    """Test Katana output parsing"""
    valid_output = """https://example.com/
https://example.com/about
https://api.example.com/v1/users
https://evil-target.com/"""

    with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False) as f:
        f.write(valid_output)
        input_file = f.name

    with tempfile.NamedTemporaryFile(mode='w', suffix='.jsonl', delete=False) as f:
        output_file = f.name

    try:
        code, out, err = run_bash_parser("parse_katana_output", input_file, output_file, "example.com")
        assert code == 0, f"parse_katana_output failed: {err}"

        with open(output_file) as f:
            lines = f.read().strip().split('\n')

        for line in lines:
            if line:
                data = json.loads(line)
                assert "url" in data
                assert "host" in data
                assert "target" in data
                assert data["source"] == "katana"

    finally:
        for fname in [input_file, output_file]:
            if os.path.exists(fname):
                os.unlink(fname)

    print("✓ Katana parser contract tests passed")

if __name__ == "__main__":
    test_dnsx_parser()
    test_naabu_parser()
    test_nuclei_parser()
    test_hosts_jsonl_parser()
    test_web_ports_extraction()
    test_katana_parser()
    print("\nAll contract tests passed!")