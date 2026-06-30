#!/usr/bin/env python3

# -----------------------------------------------------------------------------
# Author: Simone Machetti
#
# Regression: run sim / syn / post-syn-sim / post-syn-sta / post-syn-dpa for
# every architecture and report PASS / FAIL per stage. Exit 0 iff all stages
# pass. See scripts/flow/regres/README.md for details.
# -----------------------------------------------------------------------------

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

CLK = "1.35"
DIST_TYPE = "0"
STAGES = ("sim", "syn", "post-syn-sim", "post-syn-sta", "post-syn-dpa")

# slug | label | top_level | syn_params | sim_extra | max_val_a | max_val_b
ARCHES = [
    ("bas_4x8",           "Baseline 4x8",             "top_bas_4x8",           "IS_PIPELINED=1 MULT_TYPE=0", "IS_PIPELINED=1 MULT_TYPE=0", 7,   127),
    ("bas_8x8",           "Baseline 8x8",             "top_bas_8x8",           "IS_PIPELINED=1 MULT_TYPE=0", "IS_PIPELINED=1 MULT_TYPE=0", 127, 127),
    ("bas_4x8_sc",        "Baseline 4x8 SC",          "top_bas_4x8_sc",        "IS_PIPELINED=1 MULT_TYPE=0", "IS_PIPELINED=1 MULT_TYPE=0", 7,   127),
    ("win_4x8",           "Winograd 4x8",             "top_win_4x8",           "IS_PIPELINED=1 MULT_TYPE=0", "IS_PIPELINED=1 MULT_TYPE=0", 7,   127),
    ("win_4x8_sc",        "Winograd 4x8 SC",          "top_win_4x8_sc",        "IS_PIPELINED=1 MULT_TYPE=0", "IS_PIPELINED=1 MULT_TYPE=0", 7,   127),
    ("sqr_4x8_sc",        "Square 4x8 SC",            "top_sqr_4x8_sc",        "IS_PIPELINED=1",             "IS_PIPELINED=1",             7,   127),
    ("sqr_8x8",           "Square 8x8",               "top_sqr_8x8",           "IS_PIPELINED=1",             "IS_PIPELINED=1",             127, 127),
    ("sqr_4x8_alpha",     "Square 4x8 Alpha",         "top_sqr_4x8_sc_alpha",  "IS_PIPELINED=1 IS_SQUARE=0", "IS_PIPELINED=1 IS_SQUARE=0", 7,   None),
    ("sqr_4x8_alpha_sqr", "Square 4x8 Alpha Squared", "top_sqr_4x8_sc_alpha",  "IS_PIPELINED=1 IS_SQUARE=1", "IS_PIPELINED=1 IS_SQUARE=1", 7,   None),
    ("sqr_8x8_alpha",     "Square 8x8 Alpha",         "top_sqr_8x8_alpha",     "IS_PIPELINED=1 IS_SQUARE=0", "IS_PIPELINED=1 IS_SQUARE=0", 127, None),
    ("sqr_8x8_alpha_sqr", "Square 8x8 Alpha Squared", "top_sqr_8x8_alpha",     "IS_PIPELINED=1 IS_SQUARE=1", "IS_PIPELINED=1 IS_SQUARE=1", 127, None),
]


def repo_root() -> Path:
    repo_home = os.environ.get("REPO_HOME")
    if not repo_home:
        sys.exit("REPO_HOME is not set; run `source sourceme.sh` first.")
    return Path(repo_home) / "projects" / "ai-core-legacy"


def make_call(target: str, params: dict[str, str], log: Path) -> bool:
    args = ["make", target] + [f"{k}={v}" for k, v in params.items()]
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open("w") as f:
        rc = subprocess.run(args, stdout=f, stderr=subprocess.STDOUT).returncode
    return rc == 0


def sim_params(sim_extra: str, max_a: int, max_b: int | None) -> str:
    parts = [sim_extra, f"MAX_VAL_A={max_a}", f"DIST_TYPE={DIST_TYPE}"]
    if max_b is not None:
        parts.append(f"MAX_VAL_B={max_b}")
    return " ".join(parts)


def stage_params(arch, stage: str) -> dict[str, str]:
    slug, _, top, syn_p, sim_e, max_a, max_b = arch
    common = {"TOP_LEVEL": top, "CLK_PERIOD_NS": CLK}
    syn_dir = f"{slug}_syn"
    sp = sim_params(sim_e, max_a, max_b)

    if stage == "sim":
        return {**common, "OUT_DIR": f"{slug}_sim", "PARAMS": sp}
    if stage == "syn":
        return {"TOP_LEVEL": top, "OUT_DIR": syn_dir, "PARAMS": syn_p}
    if stage == "post-syn-sim":
        return {**common, "OUT_DIR": f"{slug}_post_syn_sim",
                "NETLIST_DIR": syn_dir, "PARAMS": sp}
    if stage == "post-syn-sta":
        return {**common, "OUT_DIR": f"{slug}_post_syn_sta", "NETLIST_DIR": syn_dir}
    if stage == "post-syn-dpa":
        return {**common, "OUT_DIR": f"{slug}_post_syn_dpa",
                "NETLIST_DIR": syn_dir, "VCD_DIR": f"{slug}_post_syn_sim"}
    raise ValueError(f"Unknown stage: {stage}")


def main() -> int:
    root = repo_root()
    os.chdir(root)
    log_dir = root / "imp" / "_regres_logs"

    results: list[tuple[str, str, bool]] = []
    for arch in ARCHES:
        for stage in STAGES:
            log = log_dir / f"{arch[0]}_{stage}.log"
            ok = make_call(stage, stage_params(arch, stage), log)
            results.append((stage, arch[1], ok))

    passes = sum(1 for *_, ok in results if ok)
    fails = len(results) - passes

    print("\nRegression results:")
    print("-------------------")
    for stage, label, ok in results:
        tag = "PASS" if ok else "FAIL"
        print(f"  {tag}  {stage:<13} {label}")
    print("-------------------")
    print(f"PASS: {passes}  FAIL: {fails}  TOTAL: {len(results)}\n")
    return 0 if fails == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
