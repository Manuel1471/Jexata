#!/usr/bin/env python3
"""Generate bounded JSONata expressions and compare Jexata with jsonata.js."""

import argparse
import json
from pathlib import Path
import random
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
REFERENCE_SHA = "8ee4476f8a228bfc7a62979ae0a9c13a4043cd03"


def numeric_expression(rng, depth):
    leaves = ["a", "b", "$sum(orders.price)", str(rng.randint(-10, 20))]
    if depth == 0 or rng.random() < 0.4:
        return rng.choice(leaves)
    left = numeric_expression(rng, depth - 1)
    right = numeric_expression(rng, depth - 1)
    return f"({left} {rng.choice(['+', '-', '*'])} {right})"


def expression(rng):
    number = rng.randint(-5, 20)
    threshold = rng.randint(0, 9)
    choices = [
        lambda: f"a + {number}",
        lambda: f"(a * {number}) + b",
        lambda: f"a > {threshold} ? a : b",
        lambda: f"a = {number}",
        lambda: f"a in [{number},{threshold},b]",
        lambda: f"[a,b,{number}]",
        lambda: f"{{'x':a,'y':b+{number}}}",
        lambda: "orders.price",
        lambda: f"orders[price > {threshold}].price",
        lambda: f"orders[{rng.choice([0, 1, -1])}].price",
        lambda: "$sum(orders.price)",
        lambda: "s & '-' & $string(a)",
        lambda: "$trim(s)",
        lambda: "$uppercase(s)",
        lambda: "$contains(s,/foo/)",
        lambda: "$split(s,/foo/)",
        lambda: "$replace(s,/foo/,'bar')",
        lambda: "$map(orders,function($o){$o.price*2})",
        lambda: "$reduce(orders,function($a,$o){$a+$o.price},0)",
        lambda: numeric_expression(rng, 2),
        lambda: f"{numeric_expression(rng, 2)} > {numeric_expression(rng, 1)}",
        lambda: f"{numeric_expression(rng, 1)} > 0 ? {numeric_expression(rng, 2)} : b",
        lambda: f"[{numeric_expression(rng, 2)},{numeric_expression(rng, 1)}]",
        lambda: f"{{'n':{numeric_expression(rng, 2)},'ok':a>{threshold}}}",
    ]
    return rng.choice(choices)()


def normalize(result):
    if result.get("kind") != "value":
        return result
    return result


def run(command, expected):
    completed = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, check=True)
    rows = [json.loads(line) for line in completed.stdout.splitlines() if line.startswith("{")]
    if len(rows) != expected:
        raise RuntimeError(f"Expected {expected} results, got {len(rows)}: {completed.stderr}")
    return {row["name"]: normalize(row["result"]) for row in rows}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", type=Path, default=Path("/tmp/jexata-reference-2.2.0"))
    parser.add_argument("--seed", type=int, default=20261103)
    parser.add_argument("--count", type=int, default=500)
    parser.add_argument("--output", type=Path, default=ROOT / "docs/differential_fuzz_results.json")
    args = parser.parse_args()
    if args.count < 1:
        parser.error("--count must be positive")
    reference = args.reference.resolve()
    sha = subprocess.check_output(["git", "-C", str(reference), "rev-parse", "HEAD"], text=True).strip()
    if sha != REFERENCE_SHA:
        parser.error(f"Expected jsonata.js v2.2.0 at {REFERENCE_SHA}, got {sha}")

    rng = random.Random(args.seed)
    cases = []
    for index in range(args.count):
        data = {
            "a": rng.randint(-20, 20), "b": rng.randint(-20, 20),
            "s": rng.choice(["foo bar", "  foo  bar  ", "no match", "foofoo"]),
            "orders": [{"price": rng.randint(0, 20)} for _ in range(rng.randint(0, 8))],
        }
        cases.append({"name": f"case_{index:05}", "source": expression(rng), "data": data})

    with tempfile.TemporaryDirectory(prefix="jexata-fuzz-") as temporary:
        input_path = Path(temporary) / "cases.json"
        input_path.write_text(json.dumps(cases))
        left = run(["mix", "run", str(ROOT / "scripts/differential_eval.exs"), str(input_path)], len(cases))
        right = run(["node", str(ROOT / "scripts/differential_eval.js"), str(input_path),
                     str(reference / "src/jsonata.js")], len(cases))

    mismatches = [
        {"case": case, "jexata": left[case["name"]], "jsonata_js": right[case["name"]]}
        for case in cases if left[case["name"]] != right[case["name"]]
    ]
    output = {"seed": args.seed, "count": args.count, "reference_commit": sha,
              "mismatches": mismatches}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, indent=2, sort_keys=True) + "\n")
    print(f"{args.count} cases, {len(mismatches)} mismatches; wrote {args.output}")
    for mismatch in mismatches[:10]:
        print(json.dumps(mismatch, ensure_ascii=False))
    if mismatches:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
