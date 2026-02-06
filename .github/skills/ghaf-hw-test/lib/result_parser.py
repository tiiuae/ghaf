#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
"""
Robot Framework output.xml parser and fix proposal generator.

This module parses Robot Framework test results and generates
actionable fix proposals for failing tests.
"""

import sys
import re
from pathlib import Path

try:
    import xml.etree.ElementTree as ET
    import yaml
except ImportError as e:
    print(f"Missing dependency: {e}", file=sys.stderr)
    print("Run from nix-shell or install: pyyaml", file=sys.stderr)
    sys.exit(1)


class TestResult:
    """Represents a single test result."""

    def __init__(self, name: str, status: str, message: str = "",
                 suite: str = "", tags: list = None):
        self.name = name
        self.status = status  # PASS, FAIL, SKIP
        self.message = message
        self.suite = suite
        self.tags = tags or []

    def __repr__(self):
        return f"TestResult({self.name}, {self.status})"


class ResultParser:
    """Parses Robot Framework output.xml files."""

    def __init__(self, output_xml: str):
        self.output_xml = Path(output_xml)
        self.results: list[TestResult] = []
        self._parent_map: dict[ET.Element, ET.Element] = {}
        self.total = 0
        self.passed = 0
        self.failed = 0
        self.skipped = 0

    def parse(self) -> list[TestResult]:
        """Parse the output.xml and return list of TestResult objects."""
        if not self.output_xml.exists():
            raise FileNotFoundError(f"Output file not found: {self.output_xml}")

        tree = ET.parse(self.output_xml)
        root = tree.getroot()

        # Build parent map once for efficient lookups
        self._parent_map = {c: p for p in root.iter() for c in p}

        # Find all test elements
        for test in root.iter("test"):
            name = test.get("name", "Unknown")

            # Get status
            status_elem = test.find("status")
            if status_elem is not None:
                status = status_elem.get("status", "UNKNOWN")
                message = status_elem.text or ""
            else:
                status = "UNKNOWN"
                message = ""

            # Get tags
            tags = []
            for tag in test.findall(".//tag"):
                if tag.text:
                    tags.append(tag.text)

            # Get suite name from parent
            parent = test
            suite = ""
            while parent is not None:
                parent = self._get_parent(root, parent)
                if parent is not None and parent.tag == "suite":
                    suite = parent.get("name", "")
                    break

            result = TestResult(
                name=name,
                status=status,
                message=message,
                suite=suite,
                tags=tags
            )
            self.results.append(result)

            # Update counts
            self.total += 1
            if status == "PASS":
                self.passed += 1
            elif status == "FAIL":
                self.failed += 1
            else:
                self.skipped += 1

        return self.results

    def _get_parent(self, root: ET.Element, child: ET.Element) -> ET.Element | None:
        """Find parent element using the cached parent map."""
        return self._parent_map.get(child)

    def get_failures(self) -> list[TestResult]:
        """Return only failing tests."""
        return [r for r in self.results if r.status == "FAIL"]

    def summary(self) -> str:
        """Return a summary string."""
        return (
            f"Total: {self.total}, "
            f"Passed: {self.passed}, "
            f"Failed: {self.failed}, "
            f"Skipped: {self.skipped}"
        )


class FailureAnalyzer:
    """Analyzes test failures and maps them to Ghaf modules."""

    def __init__(self, config_path: str):
        self.config_path = Path(config_path)
        self.config = self._load_config()
        self.failure_patterns = self.config.get("failure_patterns", {})

    def _load_config(self) -> dict:
        """Load configuration from YAML file."""
        if not self.config_path.exists():
            return {}
        with open(self.config_path) as f:
            return yaml.safe_load(f) or {}

    def analyze(self, result: TestResult) -> dict:
        """Analyze a single test failure and return analysis."""
        analysis = {
            "test_name": result.name,
            "suite": result.suite,
            "message": result.message,
            "category": "unknown",
            "likely_modules": [],
            "suggestion": "",
            "patterns_matched": []
        }

        # Match against known failure patterns
        for category, pattern_config in self.failure_patterns.items():
            patterns = pattern_config.get("patterns", [])
            for pattern in patterns:
                if re.search(pattern, result.message, re.IGNORECASE):
                    analysis["category"] = category
                    analysis["likely_modules"] = pattern_config.get("likely_modules", [])
                    analysis["suggestion"] = pattern_config.get("suggestion", "")
                    analysis["patterns_matched"].append(pattern)

        return analysis


class FixProposer:
    """Generates fix proposals for test failures."""

    def __init__(self, repo_root: str = "."):
        self.repo_root = Path(repo_root)

    def propose(self, analysis: dict) -> str:
        """Generate a fix proposal for a test failure."""
        lines = []
        lines.append(f"## Fix Proposal: {analysis['test_name']}")
        lines.append("")

        if analysis["suite"]:
            lines.append(f"**Test Suite:** {analysis['suite']}")
        lines.append(f"**Category:** {analysis['category']}")
        lines.append("")

        if analysis["message"]:
            lines.append("### Error Message")
            lines.append("```")
            lines.append(analysis["message"][:500])  # Truncate long messages
            lines.append("```")
            lines.append("")

        if analysis["likely_modules"]:
            lines.append("### Likely Code Locations")
            for module in analysis["likely_modules"]:
                full_path = self.repo_root / module
                if full_path.exists():
                    lines.append(f"- ✓ `{module}` (exists)")
                else:
                    lines.append(f"- ? `{module}` (check path)")
            lines.append("")

        if analysis["suggestion"]:
            lines.append("### Suggested Action")
            lines.append(analysis["suggestion"])
            lines.append("")

        if analysis["patterns_matched"]:
            lines.append("### Matched Patterns")
            for pattern in analysis["patterns_matched"]:
                lines.append(f"- `{pattern}`")
            lines.append("")

        return "\n".join(lines)


def main():
    """Main entry point for result parsing and analysis."""
    if len(sys.argv) < 3:
        print("Usage: result_parser.py <output.xml> <config.yaml> [propose_fixes]")
        sys.exit(1)

    output_xml = sys.argv[1]
    config_path = sys.argv[2]
    propose_fixes = len(sys.argv) > 3 and sys.argv[3].lower() == "true"

    # Parse results
    parser = ResultParser(output_xml)
    try:
        parser.parse()
    except FileNotFoundError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    except ET.ParseError as e:
        print(f"Error parsing XML: {e}", file=sys.stderr)
        sys.exit(1)

    # Print summary
    print("=" * 60)
    print("TEST RESULTS SUMMARY")
    print("=" * 60)
    print(parser.summary())
    print("")

    # Get failures
    failures = parser.get_failures()

    if not failures:
        print("✓ All tests passed!")
        sys.exit(0)

    print(f"FAILURES ({len(failures)}):")
    print("-" * 60)

    for failure in failures:
        print(f"  ✗ {failure.name}")
        if failure.suite:
            print(f"    Suite: {failure.suite}")
        if failure.message:
            # Truncate long messages
            msg = failure.message[:200]
            if len(failure.message) > 200:
                msg += "..."
            print(f"    Message: {msg}")
        print("")

    if propose_fixes:
        print("=" * 60)
        print("FIX PROPOSALS")
        print("=" * 60)
        print("")

        analyzer = FailureAnalyzer(config_path)
        proposer = FixProposer()

        for failure in failures:
            analysis = analyzer.analyze(failure)
            proposal = proposer.propose(analysis)
            print(proposal)
            print("-" * 60)
            print("")

    sys.exit(1)  # Exit with error code since there are failures


if __name__ == "__main__":
    main()
