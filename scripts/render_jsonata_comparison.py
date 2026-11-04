#!/usr/bin/env python3
"""Refresh the generated benchmark tables from the recorded JSON observations."""

import argparse
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
START = "<!-- BEGIN GENERATED RESULTS -->"
END = "<!-- END GENERATED RESULTS -->"
CATEGORIES = [
    ("compile", "Compilation"),
    ("scalar", "Scalar expressions"),
    ("path", "Paths and predicates"),
    ("aggregate", "Aggregates and grouping"),
    ("collection", "Collections and sorting"),
    ("higher_order", "Higher-order functions"),
    ("numeric", "Numeric functions"),
    ("string", "String functions"),
    ("regex", "Regular expressions"),
    ("datetime", "Date and time"),
]


def timing(values):
    return f"{values['median']:,.2f} [{values['min']:,.2f}–{values['max']:,.2f}]"


def render(results):
    summary = results["summary"]
    lines = [
        START,
        f"**{results['case_count']} expressions:** {results['comparable_count']} matching results; "
        f"{results['mismatch_count']} "
        f"{'mismatch' if results['mismatch_count'] == 1 else 'mismatches'} "
        "excluded from timing ratios.",
        "",
        "| Category | Matching cases | Lower Jexata median | Lower JS median |",
        "| --- | ---: | ---: | ---: |",
    ]
    for key, title in CATEGORIES:
        rows = [value for value in summary.values() if value["category"] == key]
        left = sum(value["js_over_jexata"] > 1 for value in rows)
        lines.append(f"| {title} | {len(rows)} | {left} | {len(rows) - left} |")

    for key, title in CATEGORIES:
        rows = [(name, value) for name, value in summary.items() if value["category"] == key]
        lines.extend([
            "", f"### {title}", "",
            "| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |",
            "| --- | --- | ---: | ---: | ---: |",
        ])
        for name, value in rows:
            lines.append(
                f"| `{name}` | `{value['source']}` | {timing(value['jexata_us'])} | "
                f"{timing(value['jsonata_js_us'])} | {value['js_over_jexata']:.2f}× |"
            )
    lines.extend(["", END])
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=ROOT / "docs/jsonata_js_comparison.json")
    parser.add_argument("--output", type=Path, default=ROOT / "docs/JSONATA_JS_COMPARISON.md")
    args = parser.parse_args()
    results = json.loads(args.input.read_text())
    if results["case_count"] != results["comparable_count"] + results["mismatch_count"]:
        parser.error("Case counts in benchmark JSON do not add up")
    document = args.output.read_text()
    if document.count(START) != 1 or document.count(END) != 1:
        parser.error("Markdown document needs one generated-results marker pair")
    before, after_start = document.split(START, 1)
    _, after = after_start.split(END, 1)
    args.output.write_text(before + render(results) + after)
    print(f"Updated {args.output} from {args.input}")


if __name__ == "__main__":
    main()
