#!/usr/bin/env python3
"""Compare Jexata and jsonata.js v2.2.0 on identical data and expressions."""

import argparse
import json
import os
from pathlib import Path
import statistics
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
CASES = [
    ("compile_field", "customer.name", "compile", 5000),
    ("field", "customer.name", "evaluate", 5000),
    ("filter", "orders[price > 50].price", "evaluate", 300),
    ("sum", "$sum(orders.price)", "evaluate", 300),
    ("map_lambda", "$map(orders,function($o){$o.price*2})", "evaluate", 100),
    ("reduce_lambda", "$reduce(orders,function($a,$o){$a+$o.price},0)", "evaluate", 100),
    ("sort_comparator", "$sort(orders,function($a,$b){$a.price>$b.price})", "evaluate", 30),
    ("group_object", "orders{customer:$sum(price)}", "evaluate", 50),
    ("index_zero", "orders[0].price", "evaluate", 1000),
    ("number_decimal", "$map(orders,function($o){$number($o.decimal)})", "evaluate", 50),
    ("trim", "$map(orders,function($o){$trim($o.padded)})", "evaluate", 50),
    ("replace", "$map(orders,function($o){$replace($o.text,/Order/,'Item')})", "evaluate", 50),
]


def run(command, cwd=ROOT, env=None):
    completed = subprocess.run(command, cwd=cwd, env=env, text=True, capture_output=True, check=True)
    rows = [json.loads(line) for line in completed.stdout.splitlines() if line.startswith("{")]
    if len(rows) != len(CASES):
        raise RuntimeError(f"Expected {len(CASES)} benchmark rows from {command[0]}, got {len(rows)}")
    return {row["case"]: row for row in rows}


def median_range(values):
    return {"median": statistics.median(values), "min": min(values), "max": max(values)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", type=Path, default=Path("/tmp/jexata-reference-2.2.0"))
    parser.add_argument("--rounds", type=int, default=5)
    parser.add_argument("--output", type=Path, default=ROOT / "docs/jsonata_js_comparison.json")
    args = parser.parse_args()
    if args.rounds < 1:
        parser.error("--rounds must be positive")
    reference = args.reference.resolve()
    package = json.loads((reference / "package.json").read_text())
    if package["name"] != "jsonata" or package["version"] != "2.2.0":
        parser.error("--reference must point to a jsonata.js v2.2.0 checkout")
    reference_sha = subprocess.check_output(["git", "-C", str(reference), "rev-parse", "HEAD"], text=True).strip()
    if reference_sha != "8ee4476f8a228bfc7a62979ae0a9c13a4043cd03":
        parser.error(f"Unexpected reference commit {reference_sha}")

    orders = [
        {"price": number, "customer": f"customer{number % 10}",
         "decimal": f"{number}.50", "padded": f"  Order {number}   Foo  ",
         "text": f"Order {number} Foo"}
        for number in range(1, 1001)
    ]
    fixture = {
        "data": {"customer": {"name": "Ada"}, "orders": orders},
        "cases": [dict(name=name, source=source, mode=mode, iterations=iterations)
                  for name, source, mode, iterations in CASES],
    }
    measurements = {"jexata": {name: [] for name, *_ in CASES},
                    "jsonata_js": {name: [] for name, *_ in CASES}}
    with tempfile.TemporaryDirectory(prefix="jexata-js-compare-") as temporary:
        fixture_path = Path(temporary) / "fixture.json"
        fixture_path.write_text(json.dumps(fixture))
        commands = {
            "jexata": ["mix", "run", str(ROOT / "scripts/benchmark_vs_jsonata.exs"), str(fixture_path)],
            "jsonata_js": ["node", str(ROOT / "scripts/benchmark_vs_jsonata.js"), str(fixture_path),
                           str(reference / "src/jsonata.js")],
        }
        for round_number in range(args.rounds):
            order = ("jexata", "jsonata_js") if round_number % 2 == 0 else ("jsonata_js", "jexata")
            results = {}
            for engine in order:
                env = dict(os.environ, MIX_ENV="prod") if engine == "jexata" else None
                results[engine] = run(commands[engine], env=env)
                print(f"round {round_number + 1}/{args.rounds}: {engine}", flush=True)
            for name, source, mode, iterations in CASES:
                left, right = results["jexata"][name], results["jsonata_js"][name]
                if left["result"] != right["result"]:
                    raise RuntimeError(f"Different result for {name}: Jexata {left['result']!r}, JS {right['result']!r}")
                for engine in measurements:
                    measurements[engine][name].append(results[engine][name]["ns_per_op"] / 1000)

    summary = {}
    for name, source, mode, iterations in CASES:
        left = median_range(measurements["jexata"][name])
        right = median_range(measurements["jsonata_js"][name])
        summary[name] = {"source": source, "mode": mode, "iterations": iterations,
                         "jexata_us": left, "jsonata_js_us": right,
                         "js_over_jexata": right["median"] / left["median"]}
        print(f"{name:18} Jexata {left['median']:8.2f} µs  JS {right['median']:8.2f} µs  "
              f"JS/Jexata {summary[name]['js_over_jexata']:6.2f}×")
    output = {"reference_commit": reference_sha,
              "jexata_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
              "node_version": subprocess.check_output(["node", "--version"], text=True).strip(),
              "rounds": args.rounds, "samples_us": measurements, "summary": summary}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, indent=2, sort_keys=True) + "\n")
    print(f"wrote {args.output}")


if __name__ == "__main__":
    main()
