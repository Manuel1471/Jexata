#!/usr/bin/env python3
"""Benchmark two local commits in alternating isolated Git worktrees."""

import argparse
import json
import os
from pathlib import Path
import statistics
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
BENCHMARK = ROOT / "scripts" / "benchmark_compare.exs"


def command(*args, cwd=ROOT, env=None):
    return subprocess.run(args, cwd=cwd, env=env, check=True, text=True, capture_output=True)


def checkout(commit, directory):
    command("git", "worktree", "add", "--detach", str(directory), commit)


def measure(directory, benchmark):
    env = dict(os.environ, MIX_ENV="prod")
    result = command("mix", "run", str(benchmark), cwd=directory, env=env)
    return [json.loads(line) for line in result.stdout.splitlines() if line.startswith("{")]


def summarize(samples):
    values = [sample["us_per_op"] for sample in samples]
    return {
        "us_median": statistics.median(values),
        "us_min": min(values),
        "us_max": max(values),
        "reductions_median": statistics.median(sample["reductions_per_op"] for sample in samples),
        "minor_gcs_median": statistics.median(sample["minor_gcs_per_op"] for sample in samples),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", required=True)
    parser.add_argument("--current", required=True)
    parser.add_argument("--rounds", type=int, default=5)
    parser.add_argument("--benchmark", type=Path, default=BENCHMARK)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.rounds < 1:
        parser.error("--rounds must be positive")

    commits = {
        "base": command("git", "rev-parse", args.base).stdout.strip(),
        "current": command("git", "rev-parse", args.current).stdout.strip(),
    }
    raw = {"base": {}, "current": {}}
    worktrees = []

    with tempfile.TemporaryDirectory(prefix="jexata-compare-") as temporary:
        directories = {name: Path(temporary) / name for name in commits}
        try:
            for name, directory in directories.items():
                checkout(commits[name], directory)
                worktrees.append(directory)

            for round_number in range(args.rounds):
                order = ("base", "current") if round_number % 2 == 0 else ("current", "base")
                for name in order:
                    rows = measure(directories[name], args.benchmark.resolve())
                    if len(rows) != len({row["case"] for row in rows}):
                        raise RuntimeError(f"Duplicate benchmark case in {name}")
                    for row in rows:
                        raw[name].setdefault(row["case"], []).append(row)
                    print(f"round {round_number + 1}/{args.rounds}: {name}: {len(rows)} cases", flush=True)
        finally:
            for directory in reversed(worktrees):
                command("git", "worktree", "remove", "--force", str(directory))

    if raw["base"].keys() != raw["current"].keys():
        raise RuntimeError("The checkouts did not run the same workload names")

    summary = {}
    for name in raw["base"]:
        base = raw["base"][name]
        current = raw["current"][name]
        if len(base) != args.rounds or len(current) != args.rounds:
            raise RuntimeError(f"Incomplete rounds for {name}")
        if len({row["result_hash"] for row in base + current}) != 1:
            raise RuntimeError(f"Different result for {name}")
        summary[name] = {
            "mode": base[0]["mode"],
            "iterations": base[0]["iterations"],
            "result_hash": base[0]["result_hash"],
            "base": summarize(base),
            "current": summarize(current),
        }

    output = {
        "commits": commits,
        "rounds": args.rounds,
        "order": "alternating base/current and current/base",
        "raw": raw,
        "summary": summary,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, indent=2, sort_keys=True) + "\n")
    print(f"wrote {args.output}")


if __name__ == "__main__":
    main()
