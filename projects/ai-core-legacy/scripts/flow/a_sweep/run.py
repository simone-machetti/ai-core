#!/usr/bin/env python3

# -----------------------------------------------------------------------------
# Author: Simone Machetti
#
# A-magnitude sweep at fixed MAX_VAL_B=127, DIST_TYPE=1. Runs post-syn-sim and
# post-syn-dpa for each (arch, A) tuple. Synthesis directories are reused from
# scripts/flow/dyn_range/run.py (`<slug>_dyn_syn`). Idempotent: skips
# points whose DPA report already exists. See scripts/flow/a_sweep/README.md.
# -----------------------------------------------------------------------------

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

CLK = "1.35"
A_VALUES = (0, 1, 2, 3, 4, 5, 6, 7)
B_FIXED = 127
SUFFIX = "asw"
SYN_SUFFIX = "dyn"

# slug | top_level | syn_params | sim_params | has_b
ARCHES = [
    ("bas_4x8",           "top_bas_4x8",
        "IS_PIPELINED=1 MULT_TYPE=0",
        "IS_PIPELINED=1 MULT_TYPE=0 DIST_TYPE=1 MU_SCALE=0.875 SIGMA_SCALE=0.125",
        True),
    ("sqr_4x8_sc",        "top_sqr_4x8_sc",
        "IS_PIPELINED=1",
        "IS_PIPELINED=1 DIST_TYPE=1 MU_SCALE=0.875 SIGMA_SCALE=0.125",
        True),
    ("sqr_4x8_alpha_sum", "top_sqr_4x8_sc_alpha",
        "IS_PIPELINED=0 IS_SQUARE=0",
        "IS_PIPELINED=0 IS_SQUARE=0 DIST_TYPE=1 MU_SCALE=0.875 SIGMA_SCALE=0.125",
        False),
    ("sqr_4x8_alpha_sqr", "top_sqr_4x8_sc_alpha",
        "IS_PIPELINED=0 IS_SQUARE=1",
        "IS_PIPELINED=0 IS_SQUARE=1 DIST_TYPE=1 MU_SCALE=0.875 SIGMA_SCALE=0.125",
        False),
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


def ensure_synthesis(root: Path) -> None:
    print("=== Synthesis (reused from dyn_range) ===")
    for slug, top, syn_params, _, _ in ARCHES:
        syn_dir = f"{slug}_{SYN_SUFFIX}_syn"
        area_rpt = root / "imp" / syn_dir / "report" / "area.rpt"
        if area_rpt.exists():
            print(f"  [skip] {syn_dir}")
            continue
        print(f"  [run]  {syn_dir}")
        log = root / "imp" / f"{syn_dir}.log"
        ok = make_call("syn", {"TOP_LEVEL": top, "OUT_DIR": syn_dir, "PARAMS": syn_params}, log)
        if not ok or not area_rpt.exists():
            sys.exit(f"  ERROR: syn {slug} failed; see {log}")


def run_point(root: Path, slug: str, top: str, sim_params: str, syn_dir: str,
              tag: str, extra_params: str) -> None:
    pss_dir = f"{slug}_{SUFFIX}_{tag}_post_syn_sim"
    dpa_dir = f"{slug}_{SUFFIX}_{tag}_dpa"
    dpa_rpt = root / "imp" / dpa_dir / "report" / "power_summary.rpt"
    if dpa_rpt.exists():
        print(f"  [skip] {dpa_dir}")
        return
    print(f"  [run]  {slug} {tag}")

    pss_log = root / "sim" / f"{pss_dir}.log"
    ok = make_call("post-syn-sim", {
        "TOP_LEVEL": top, "CLK_PERIOD_NS": CLK,
        "OUT_DIR": pss_dir, "NETLIST_DIR": syn_dir,
        "PARAMS": f"{sim_params} {extra_params}",
    }, pss_log)
    vcd = root / "sim" / pss_dir / "output" / "activity.vcd"
    if not ok or not vcd.exists():
        print(f"    ERROR: post-syn-sim failed; see {pss_log}")
        return

    dpa_log = root / "imp" / f"{dpa_dir}.log"
    make_call("post-syn-dpa", {
        "TOP_LEVEL": top, "CLK_PERIOD_NS": CLK,
        "OUT_DIR": dpa_dir, "NETLIST_DIR": syn_dir, "VCD_DIR": pss_dir,
    }, dpa_log)
    if not dpa_rpt.exists():
        print(f"    ERROR: post-syn-dpa failed; see {dpa_log}")


def main() -> int:
    root = repo_root()
    os.chdir(root)
    (root / "imp").mkdir(exist_ok=True)
    (root / "sim").mkdir(exist_ok=True)

    ensure_synthesis(root)

    print("\n=== Sweep ===")
    for slug, top, _, sim_params, has_b in ARCHES:
        syn_dir = f"{slug}_{SYN_SUFFIX}_syn"
        for a in A_VALUES:
            if has_b:
                run_point(root, slug, top, sim_params, syn_dir,
                          f"a{a}_b{B_FIXED}", f"MAX_VAL_A={a} MAX_VAL_B={B_FIXED}")
            else:
                run_point(root, slug, top, sim_params, syn_dir,
                          f"a{a}", f"MAX_VAL_A={a}")

    print("\nDone.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
