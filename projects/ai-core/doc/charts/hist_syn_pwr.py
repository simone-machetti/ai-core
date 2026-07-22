# -----------------------------------------------------------------------------
# Author: Simone Machetti
#
# Description:
#   Stacked-bar chart of VCD-annotated dynamic power for the baseline (top_NxN)
#   and square (top_NxN_sqr) PE grids at 8x8 and 16x16, split into PE / Dispatch
#   / Alpha-Beta / Clock (ICG) / Others. Unlike the area chart, all four bars are
#   assembled from the per-component unit powers measured on the complete 2x2
#   grids at 100 vectors/mode (imp/dpa_2x2[_sqr]/report/power_hierarchy.rpt) - gate-level simulation
#   of an 8x8 or 16x16 grid does not fit in memory - and collected per category
#   in doc/data/res_syn_pwr.xlsx. Colours follow hist_syn_area.py, with Clock
#   added: power has a clock term area does not. Writes hist_syn_pwr.png next to
#   this.
# -----------------------------------------------------------------------------

from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Patch

UNIT_BASELINE = {
    "PE":         {"pe":          0.63350, "icg_pe": 0.02080},
    "Dispatch":   {"disp_a":      0.09425, "disp_b": 0.10500},
    "Alpha-Beta": {},
    "Clock":      {"icg_rowcol":  0.00591},
    "Others":     {"ctrl":        0.00123, "glue":   0.00000},
}

UNIT_SQUARE = {
    "PE":         {"pe_sqr":      0.50900, "icg_pe": 0.01970},
    "Dispatch":   {"disp_a_sqr":  0.12600, "disp_b_sqr": 0.10400},
    "Alpha-Beta": {"alpha":       0.40100, "beta":   0.36400},
    "Clock":      {"icg_rowcol":  0.01490},
    "Others":     {"ctrl_sqr":    0.00172, "const_sqr": 0.00001, "glue": 0.00129},
}

COUNT = {
    "pe": "N2", "pe_sqr": "N2", "icg_pe": "N2",
    "disp_a": "N", "disp_b": "N", "disp_a_sqr": "N", "disp_b_sqr": "N",
    "alpha": "N", "beta": "N", "icg_rowcol": "2N",
    "ctrl": "1", "ctrl_sqr": "1", "const_sqr": "1", "glue": "1",
}


def assemble(unit, n):
    mult = {"1": 1, "N": n, "2N": 2 * n, "N2": n * n}
    return {sec: sum(v * mult[COUNT[k]] for k, v in comps.items())
            for sec, comps in unit.items()}


bars = [
    ("Baseline 8×8",   assemble(UNIT_BASELINE, 8)),
    ("Square 8×8",     assemble(UNIT_SQUARE, 8)),
    ("Baseline 16×16", assemble(UNIT_BASELINE, 16)),
    ("Square 16×16",   assemble(UNIT_SQUARE, 16)),
]

SECTIONS = ["PE", "Alpha-Beta", "Dispatch", "Clock", "Others"]
COLORS = {
    "PE":         "#d4a480cc",
    "Dispatch":   "#ced4da",
    "Alpha-Beta": "#778d5ecc",
    "Clock":      "#9fb3c8cc",
    "Others":     "#eadbbccc",
}

width = 0.70
x = [0.0, 0.74, 1.90, 2.64]

fig, ax = plt.subplots(figsize=(9.0, 5.6))

for xi, (_, cat) in zip(x, bars):
    bottom = 0.0
    for sec in SECTIONS:
        val = cat[sec]
        if val > 0:
            ax.bar(xi, val, width, bottom=bottom, color=COLORS[sec],
                   edgecolor="black", linewidth=0.4, zorder=3)
        bottom += val

tot = [sum(c.values()) for _, c in bars]
pad = 0.012 * max(tot)
for i, (xi, t_) in enumerate(zip(x, tot)):
    label = f"{t_:.2f} mW"
    if i % 2 == 1:
        label += f"  ({t_ / tot[i - 1] - 1.0:+.1%})"
    ax.text(xi, t_ + pad, label, ha="center", va="bottom", fontsize=9)

ax.set_xticks(x)
ax.set_xticklabels([b[0] for b in bars])

ax.set_ylabel("Dynamic power [mW]")
ax.set_title("Dynamic Power — Baseline vs Square Matrix Grid (ASAP7)")
ax.set_ylim(0, max(tot) * 1.12)
ax.grid(axis="y", linestyle="--", alpha=0.35, zorder=0)

legend = [Patch(facecolor=COLORS[s], edgecolor="black", linewidth=0.4, label=s) for s in SECTIONS]
ax.legend(handles=legend, loc="upper left", frameon=False)

fig.tight_layout()
out = Path(__file__).with_name("hist_syn_pwr.png")
fig.savefig(out, dpi=200, bbox_inches="tight")
print(f"saved {out}")
for (label, cat), t_ in zip(bars, tot):
    print(f"{label:16} total={t_:8.3f} mW  " +
          "  ".join(f"{s}={cat[s]:.3f}" for s in SECTIONS))
