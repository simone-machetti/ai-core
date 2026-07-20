# -----------------------------------------------------------------------------
# Author: Simone Machetti
#
# Description:
#   Stacked-bar chart of synthesized cell area for the baseline (top_NxN) and
#   square (top_NxN_sqr) PE grids at 8x8 and 16x16, split into PE / Dispatch /
#   Alpha-Beta / Others. All four bars are measured on the complete synthesized
#   grids (imp/top_{8x8,16x16}[_sqr]/report/area.rpt), assembled per category in
#   doc/data/res_syn_area.xlsx. Others carries ctrl, const, the ICG cells and the
#   top-level glue. Colours are taken from the legacy area_ai_core_level_16.png
#   generator. Writes hist_syn_area.png next to this.
# -----------------------------------------------------------------------------

from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Patch

BASELINE_8X8 = {
    "PE":         240572.33280,
    "Dispatch":     6809.32656,
    "Alpha-Beta":      0.00000,
    "Others":         40.40118,
}

SQUARE_8X8 = {
    "PE":         208907.83872,
    "Dispatch":     5955.05520,
    "Alpha-Beta":  28720.61712,
    "Others":         63.30636,
}

BASELINE_16X16 = {
    "PE":         962289.33120,
    "Dispatch":    13618.65312,
    "Alpha-Beta":      0.00000,
    "Others":        122.98230,
}

SQUARE_16X16 = {
    "PE":         835631.35488,
    "Dispatch":    11910.11040,
    "Alpha-Beta":  57441.23424,
    "Others":        145.88748,
}

bars = [
    ("Baseline 8×8",   BASELINE_8X8),
    ("Square 8×8",     SQUARE_8X8),
    ("Baseline 16×16", BASELINE_16X16),
    ("Square 16×16",   SQUARE_16X16),
]

SECTIONS = ["PE", "Alpha-Beta", "Dispatch", "Others"]
COLORS = {
    "PE":         "#d4a480cc",
    "Dispatch":   "#ced4da",
    "Alpha-Beta": "#778d5ecc",
    "Others":     "#eadbbccc",
}

UM2_PER_MM2 = 1.0e6

width = 0.70
x = [0.0, 0.74, 1.90, 2.64]

fig, ax = plt.subplots(figsize=(9.0, 5.6))

for xi, (_, cat) in zip(x, bars):
    bottom = 0.0
    for sec in SECTIONS:
        val = cat[sec] / UM2_PER_MM2
        if val > 0:
            ax.bar(xi, val, width, bottom=bottom, color=COLORS[sec],
                   edgecolor="black", linewidth=0.4, zorder=3)
        bottom += val

tot = [sum(c.values()) for _, c in bars]
pad = 0.012 * max(tot) / UM2_PER_MM2
for i, (xi, t) in enumerate(zip(x, tot)):
    label = f"{t / UM2_PER_MM2:.3f} mm²"
    if i % 2 == 1:
        label += f"  ({t / tot[i - 1] - 1.0:+.1%})"
    ax.text(xi, t / UM2_PER_MM2 + pad, label, ha="center", va="bottom", fontsize=9)

ax.set_xticks(x)
ax.set_xticklabels([b[0] for b in bars])

ax.set_ylabel("Cell area [mm²]")
ax.set_title("Synthesis Cell Area — Baseline vs Square Matrix Grid (ASAP7)")
ax.set_ylim(0, max(tot) / UM2_PER_MM2 * 1.12)
ax.grid(axis="y", linestyle="--", alpha=0.35, zorder=0)

legend = [Patch(facecolor=COLORS[s], edgecolor="black", linewidth=0.4, label=s) for s in SECTIONS]
ax.legend(handles=legend, loc="upper left", frameon=False)

fig.tight_layout()
out = Path(__file__).with_name("hist_syn_area.png")
fig.savefig(out, dpi=200, bbox_inches="tight")
print(f"saved {out}")
for label, cat in bars:
    print(f"{label:16} total={sum(cat.values()):12.1f} um^2  " +
          "  ".join(f"{s}={cat[s]:.0f}" for s in SECTIONS))
