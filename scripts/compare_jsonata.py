#!/usr/bin/env python3
"""Compare Jexata and jsonata.js v2.2.0 on identical data and expressions."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shlex
import statistics
import subprocess
import tempfile
from typing import NamedTuple, Optional


ROOT = Path(__file__).resolve().parents[1]
class Case(NamedTuple):
    name: str
    source: str
    mode: str
    iterations: int
    category: str
    elements: Optional[int] = None


CASES = [
    Case("compile_field", "customer.name", "compile", 5000, "compile"),
    Case("compile_filter", "orders[price > 50].price", "compile", 1000, "compile"),
    Case("compile_lambda", "$map(orders,function($o){$o.price*2})", "compile", 1000, "compile"),
    Case("compile_regex", "$replace(text,/Order/,'Item')", "compile", 1000, "compile"),
    Case("compile_object", "orders{customer:$sum(price)}", "compile", 1000, "compile"),
    Case("compile_picture", "$fromMillis(1704164645000,'[Y0001]-[M01]-[D01]')", "compile", 1000, "compile"),
    Case("field", "customer.name", "evaluate", 5000, "scalar"),
    Case("missing_field", "customer.missing", "evaluate", 2000, "scalar"),
    Case("arithmetic", "(12 + 8) * 3 / 2", "evaluate", 2000, "scalar"),
    Case("conditional", "customer.name = 'Ada' ? 'yes' : 'no'", "evaluate", 2000, "scalar"),
    Case("concat", "customer.name & ' Lovelace'", "evaluate", 2000, "scalar"),
    Case("coalesce", "customer.missing ?? 'unknown'", "evaluate", 2000, "scalar"),
    Case("path_prices", "orders.price", "evaluate", 100, "path", 1000),
    Case("path_customers", "orders.customer", "evaluate", 100, "path", 1000),
    Case("filter", "orders[price > 50].price", "evaluate", 300, "path", 1000),
    Case("filter_narrow", "orders[price > 900].price", "evaluate", 100, "path", 1000),
    Case("filter_boolean", "orders[active].price", "evaluate", 100, "path", 1000),
    Case("index_zero", "orders[0].price", "evaluate", 1000, "path"),
    Case("index_last", "orders[-1].price", "evaluate", 1000, "path"),
    Case("index_binding", "orders#$i[$i < 10].price", "evaluate", 100, "path", 1000),
    Case("focus_binding", "orders@$o[$o.price > 900].price", "evaluate", 100, "path", 1000),
    Case("wildcard_order", "orders[0].*", "evaluate", 500, "path"),
    Case("order_projection", "orders[0].(price & ':' & customer)", "evaluate", 500, "path"),
    Case("descendants", "customer.**", "evaluate", 500, "path"),
    Case("sum", "$sum(orders.price)", "evaluate", 300, "aggregate", 1000),
    Case("average", "$average(orders.price)", "evaluate", 100, "aggregate", 1000),
    Case("min", "$min(orders.price)", "evaluate", 100, "aggregate", 1000),
    Case("max", "$max(orders.price)", "evaluate", 100, "aggregate", 1000),
    Case("count", "$count(orders.price)", "evaluate", 100, "aggregate", 1000),
    Case("distinct", "$distinct(orders.customer)", "evaluate", 100, "aggregate", 1000),
    Case("group_object", "orders{customer:$sum(price)}", "evaluate", 50, "aggregate", 1000),
    Case("sort_key", "orders^(price)", "evaluate", 30, "collection", 1000),
    Case("sort_comparator", "$sort(orders,function($a,$b){$a.price>$b.price})", "evaluate", 30, "collection", 1000),
    Case("reverse", "$reverse(orders.price)", "evaluate", 50, "collection", 1000),
    Case("zip", "$zip(orders.price,orders.customer)", "evaluate", 30, "collection", 1000),
    Case("append", "$append(orders.price,[1001])", "evaluate", 50, "collection", 1000),
    Case("map_lambda", "$map(orders,function($o){$o.price*2})", "evaluate", 100, "higher_order", 1000),
    Case("map_index", "$map(orders,function($o,$i){$o.price+$i})", "evaluate", 50, "higher_order", 1000),
    Case("filter_lambda", "$filter(orders,function($o){$o.price>900})", "evaluate", 50, "higher_order", 1000),
    Case("reduce_lambda", "$reduce(orders,function($a,$o){$a+$o.price},0)", "evaluate", 100, "higher_order", 1000),
    Case("each_object", "$each(customer,function($value,$key){$key & ':' & $value})", "evaluate", 500, "higher_order"),
    Case("sift_object", "$sift(customer,function($value,$key){$key='name'})", "evaluate", 500, "higher_order"),
    Case("number_decimal", "$map(orders,function($o){$number($o.decimal)})", "evaluate", 50, "numeric", 1000),
    Case("round", "$map(orders,function($o){$round($o.price / 3,2)})", "evaluate", 50, "numeric", 1000),
    Case("floor", "$map(orders,function($o){$floor($o.price / 3)})", "evaluate", 50, "numeric", 1000),
    Case("format_number", "$map(orders,function($o){$formatNumber($o.price,'#,##0')})", "evaluate", 20, "numeric", 1000),
    Case("format_integer", "$map(orders,function($o){$formatInteger($o.price,'I')})", "evaluate", 20, "numeric", 1000),
    Case("substring", "$map(orders,function($o){$substring($o.text,0,5)})", "evaluate", 50, "string", 1000),
    Case("length", "$map(orders,function($o){$length($o.text)})", "evaluate", 50, "string", 1000),
    Case("uppercase", "$map(orders,function($o){$uppercase($o.text)})", "evaluate", 50, "string", 1000),
    Case("lowercase", "$map(orders,function($o){$lowercase($o.text)})", "evaluate", 50, "string", 1000),
    Case("trim", "$map(orders,function($o){$trim($o.padded)})", "evaluate", 50, "string", 1000),
    Case("pad", "$map(orders,function($o){$pad($o.text,20,'-')})", "evaluate", 30, "string", 1000),
    Case("contains_text", "$map(orders,function($o){$contains($o.text,'Order')})", "evaluate", 50, "string", 1000),
    Case("contains_regex", "$map(orders,function($o){$contains($o.text,/Order/)})", "evaluate", 50, "regex", 1000),
    Case("replace", "$map(orders,function($o){$replace($o.text,/Order/,'Item')})", "evaluate", 50, "regex", 1000),
    Case("replace_capture", "$map(orders,function($o){$replace($o.text,/(Order) (\\d+)/,'$2 $1')})", "evaluate", 30, "regex", 1000),
    Case("split_text", "$map(orders,function($o){$split($o.text,' ')})", "evaluate", 30, "string", 1000),
    Case("split_regex", "$map(orders,function($o){$split($o.text,/\\s+/)})", "evaluate", 30, "regex", 1000),
    Case("match_regex", "$map(orders,function($o){$match($o.text,/Order/)})", "evaluate", 30, "regex", 1000),
    Case("match_scalar", "$match(orders[0].text,/Order/).match", "evaluate", 500, "regex"),
    Case("to_millis", "$map(orders,function($o){$toMillis($o.date)})", "evaluate", 30, "datetime", 1000),
    Case("from_millis", "$map(orders,function($o){$fromMillis($o.epoch)})", "evaluate", 30, "datetime", 1000),
    Case("from_millis_picture", "$map(orders,function($o){$fromMillis($o.epoch,'[Y0001]-[M01]-[D01]')})", "evaluate", 20, "datetime", 1000),
]


def run(command, cwd=ROOT, env=None):
    completed = subprocess.run(command, cwd=cwd, env=env, text=True, capture_output=True, check=True)
    rows = [json.loads(line) for line in completed.stdout.splitlines() if line.startswith("{")]
    expected = len(CASES) + (1 if command[0] == "node" else 0)
    if len(rows) != expected:
        raise RuntimeError(f"Expected {expected} benchmark rows from {command[0]}, got {len(rows)}")
    return {row["case"]: row for row in rows}


def median_range(values):
    return {"median": statistics.median(values), "min": min(values), "max": max(values)}


def preview(value):
    if isinstance(value, list):
        return {"type": "array", "length": len(value), "first_two": value[:2]}
    if isinstance(value, dict):
        return {"type": "object", "first_three": list(value.items())[:3]}
    return {"type": type(value).__name__, "value": value}


def result_digest(row):
    payload = json.dumps({"undefined": row["undefined"], "result": row["result"]},
                         sort_keys=True, ensure_ascii=False, separators=(",", ":"))
    return hashlib.sha256(payload.encode()).hexdigest()


def optional_command(*args):
    try:
        return subprocess.check_output(args, text=True, stderr=subprocess.DEVNULL).strip()
    except (OSError, subprocess.CalledProcessError):
        return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", type=Path, default=Path("/tmp/jexata-reference-2.2.0"))
    parser.add_argument("--rounds", type=int, default=7)
    parser.add_argument("--node-flags", default="", help="Flags passed directly to node")
    parser.add_argument("--output", type=Path, default=ROOT / "docs/jsonata_js_comparison.json")
    args = parser.parse_args()
    if args.rounds < 1:
        parser.error("--rounds must be positive")
    if len(CASES) < 50:
        parser.error("The comparison requires at least 50 workloads")
    if len({case.name for case in CASES}) != len(CASES):
        parser.error("Benchmark case names must be unique")
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
         "text": f"Order {number} Foo", "active": number % 2 == 0,
         "date": "2024-01-02T03:04:05Z", "epoch": 1704164645000}
        for number in range(1, 1001)
    ]
    fixture = {
        "data": {"customer": {"name": "Ada"}, "orders": orders},
        "cases": [dict(name=case.name, source=case.source, mode=case.mode,
                       iterations=case.iterations) for case in CASES],
    }
    measurements = {"jexata": {case.name: [] for case in CASES},
                    "jsonata_js": {case.name: [] for case in CASES}}
    promise_floor_us = []
    round_order = []
    comparable = {}
    mismatches = {}
    result_hashes = {"jexata": {}, "jsonata_js": {}}
    node_flags = shlex.split(args.node_flags)
    fixture_json = json.dumps(fixture)
    with tempfile.TemporaryDirectory(prefix="jexata-js-compare-") as temporary:
        fixture_path = Path(temporary) / "fixture.json"
        fixture_path.write_text(fixture_json)
        commands = {
            "jexata": ["mix", "run", str(ROOT / "scripts/benchmark_vs_jsonata.exs"), str(fixture_path)],
            "jsonata_js": ["node", *node_flags, str(ROOT / "scripts/benchmark_vs_jsonata.js"), str(fixture_path),
                           str(reference / "src/jsonata.js")],
        }
        for round_number in range(args.rounds):
            order = ("jexata", "jsonata_js") if round_number % 2 == 0 else ("jsonata_js", "jexata")
            round_order.append(list(order))
            results = {}
            for engine in order:
                env = dict(os.environ, MIX_ENV="prod") if engine == "jexata" else None
                results[engine] = run(commands[engine], env=env)
                print(f"round {round_number + 1}/{args.rounds}: {engine}", flush=True)
            for case in CASES:
                name = case.name
                left, right = results["jexata"][name], results["jsonata_js"][name]
                same_result = (left["undefined"], left["result"]) == (right["undefined"], right["result"])
                if name in comparable and comparable[name] != same_result:
                    raise RuntimeError(f"Result comparison changed between rounds for {name}")
                comparable[name] = same_result
                for engine, row in (("jexata", left), ("jsonata_js", right)):
                    digest = result_digest(row)
                    if name in result_hashes[engine] and result_hashes[engine][name] != digest:
                        raise RuntimeError(f"{engine} result changed between rounds for {name}")
                    result_hashes[engine][name] = digest
                if not same_result and name not in mismatches:
                    mismatches[name] = {
                        "source": case.source, "category": case.category,
                        "jexata_undefined": left["undefined"], "jsonata_js_undefined": right["undefined"],
                        "jexata_preview": preview(left["result"]),
                        "jsonata_js_preview": preview(right["result"]),
                    }
                for engine in measurements:
                    measurements[engine][name].append(results[engine][name]["ns_per_op"] / 1000)
            promise_floor_us.append(results["jsonata_js"]["promise_floor"]["ns_per_op"] / 1000)

    summary = {}
    for case in CASES:
        name = case.name
        if not comparable[name]:
            print(f"{name:18} RESULT MISMATCH; no timing ratio")
            continue
        left = median_range(measurements["jexata"][name])
        right = median_range(measurements["jsonata_js"][name])
        summary[name] = {"source": case.source, "mode": case.mode,
                         "category": case.category, "iterations": case.iterations,
                         "result_sha256": result_hashes["jexata"][name],
                         "jexata_us": left, "jsonata_js_us": right,
                         "js_over_jexata": right["median"] / left["median"],
                         "absolute_delta_us": right["median"] - left["median"]}
        if case.elements is not None:
            summary[name]["elements"] = case.elements
            summary[name]["jexata_ns_per_element"] = left["median"]
            summary[name]["jsonata_js_ns_per_element"] = right["median"]
        print(f"{name:18} Jexata {left['median']:8.2f} µs  JS {right['median']:8.2f} µs  "
              f"JS/Jexata {summary[name]['js_over_jexata']:6.2f}×")
    output = {"case_count": len(CASES), "comparable_count": len(summary),
              "mismatch_count": len(mismatches), "mismatches": mismatches,
              "fixture_sha256": hashlib.sha256(fixture_json.encode()).hexdigest(),
              "reference_commit": reference_sha,
              "jexata_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
              "elixir_version": subprocess.check_output(["elixir", "--version"], text=True).strip(),
              "node_version": subprocess.check_output(["node", "--version"], text=True).strip(),
              "node_flags": node_flags, "node_options": os.environ.get("NODE_OPTIONS", ""),
              "host": {"platform": platform.platform(), "machine": platform.machine(),
                       "processor": platform.processor(), "cpu_count": os.cpu_count(),
                       "mac_model": optional_command("sysctl", "-n", "hw.model"),
                       "power_source": optional_command("pmset", "-g", "batt"),
                       "power_settings": optional_command("pmset", "-g", "custom")},
              "rounds": args.rounds, "round_order": round_order,
              "promise_floor_us": {"samples": promise_floor_us, **median_range(promise_floor_us)},
              "samples_us": measurements, "summary": summary}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, indent=2, sort_keys=True) + "\n")
    print(f"wrote {args.output}")


if __name__ == "__main__":
    main()
