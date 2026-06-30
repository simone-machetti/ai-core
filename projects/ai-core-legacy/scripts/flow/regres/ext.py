#!/usr/bin/env python3

# -----------------------------------------------------------------------------
# Author: Simone Machetti
#
# Extract per-design area / f_max / power from imp/ (populated by
# scripts/flow/regres/run.py) and write doc/data/regres/results.xlsx. Designs
# without report files are skipped. See scripts/flow/regres/README.md.
# -----------------------------------------------------------------------------

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

from openpyxl import Workbook

CLK_NS = 1.35

# label | slug
DESIGNS = [
    ("Baseline 4x8",             "bas_4x8"),
    ("Baseline 8x8",             "bas_8x8"),
    ("Baseline 4x8 SC",          "bas_4x8_sc"),
    ("Winograd 4x8",             "win_4x8"),
    ("Winograd 4x8 SC",          "win_4x8_sc"),
    ("Square 4x8 SC",            "sqr_4x8_sc"),
    ("Square 8x8",               "sqr_8x8"),
    ("Square 4x8 Alpha",         "sqr_4x8_alpha"),
    ("Square 4x8 Alpha Squared", "sqr_4x8_alpha_sqr"),
    ("Square 8x8 Alpha",         "sqr_8x8_alpha"),
    ("Square 8x8 Alpha Squared", "sqr_8x8_alpha_sqr"),
]

_SLACK_RE = re.compile(r"slack \((MET|VIOLATED)\)")


def repo_root() -> Path:
    repo_home = os.environ.get("REPO_HOME")
    if not repo_home:
        sys.exit("REPO_HOME is not set; run `source sourceme.sh` first.")
    return Path(repo_home) / "projects" / "ai-core-legacy"


def read_area_um2(rpt: Path) -> float:
    for line in rpt.read_text().splitlines():
        if "Chip area for module" in line:
            return float(line.split()[-1])
    raise RuntimeError(f"No 'Chip area for module' line in {rpt}")


def read_slack_ps(rpt: Path) -> float:
    for line in rpt.read_text().splitlines():
        if _SLACK_RE.search(line):
            return float(line.split()[0])
    raise RuntimeError(f"No 'slack (MET|VIOLATED)' line in {rpt}")


def read_power_w(rpt: Path) -> float:
    for line in rpt.read_text().splitlines():
        if line.startswith("Total"):
            return float(line.split()[4])
    raise RuntimeError(f"No 'Total' row in {rpt}")


def slack_to_freq_mhz(slack_ps: float) -> float:
    return 1000.0 / (CLK_NS - slack_ps / 1000.0)


def main() -> int:
    root = repo_root()
    imp = root / "imp"
    out = root / "doc" / "data" / "regres" / "results.xlsx"
    out.parent.mkdir(parents=True, exist_ok=True)

    wb = Workbook()
    ws = wb.active
    ws.title = "data"
    ws.append(["design", "area_um2", "freq_mhz", "power_mw"])

    n_rows = 0
    for label, slug in DESIGNS:
        area_rpt = imp / f"{slug}_syn" / "report" / "area.rpt"
        sta_rpt = imp / f"{slug}_post_syn_sta" / "report" / "critical_paths.rpt"
        dpa_rpt = imp / f"{slug}_post_syn_dpa" / "report" / "power_summary.rpt"
        if not area_rpt.exists():
            print(f"  skip {label} (no synthesis results)")
            continue
        area = round(read_area_um2(area_rpt), 2)
        freq = round(slack_to_freq_mhz(read_slack_ps(sta_rpt)), 2)
        power = round(read_power_w(dpa_rpt) * 1000.0, 3)
        ws.append([label, area, freq, power])
        n_rows += 1

    if n_rows == 0:
        sys.exit("No designs had report files — nothing to extract.")

    wb.save(out)
    print(f"  wrote {out}  ({n_rows} designs)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
