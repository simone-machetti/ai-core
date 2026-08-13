# -----------------------------------------------------------------------------
# Author: Simone Machetti
#
# Description:
#   Stacked-bar chart of synthesized cell area at the PE level for the five PE
#   variants - baseline (pe), square (pe_sqr), BFP (pe_bfp), square-BFP
#   (pe_sqr_bfp) and bit-plane-A BFP (pe_bpl_a_bfp) - split into DP8-Array /
#   CPR-Tree / ACC-Array / PE glue. The composition comes from runs with the
#   internal module boundaries preserved
#   (imp/{pe,pe_sqr,pe_bfp,pe_sqr_bfp,pe_bpl_a_bfp}_hier_syn, produced by
#   scripts/run_syn_pe_area.sh): DP8-Array is the sum of the 16 dot-product
#   cores, CPR-Tree is pe_array* minus those cores, ACC-Array is acc_array*, and
#   PE glue is the remainder (operand mask + the two acc pipeline register
#   banks). Preserving a boundary blocks cross-boundary optimization, so the
#   hierarchical total runs 12-14 % above the flat PE area used everywhere else;
#   each bar is therefore SCALED to its flat total, so the shares are the
#   measured ones and the bar heights are the flat ratios (-13.0 % square,
#   -2.6 % square-BFP). Bars are NORMALIZED to the baseline PE. Absolute values
#   are collected in doc/data/res_syn_pe_area.xlsx. Writes hist_syn_pe_area.png
#   next to this.
# -----------------------------------------------------------------------------

from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Patch

HIER = {
    "Baseline":     {"DP8-Array": 3059.730, "CPR-Tree":  704.651,
                     "ACC-Array":  331.578, "PE glue":   269.672},
    "Square":       {"DP8-Array": 1892.601, "CPR-Tree":  694.183,
                     "ACC-Array":  796.491, "PE glue":   405.091},
    "Baseline-BFP": {"DP8-Array": 3091.572, "CPR-Tree": 1698.322,
                     "ACC-Array":  861.036, "PE glue":   333.824},
    "Square-BFP":   {"DP8-Array": 1892.601, "CPR-Tree": 2747.936,
                     "ACC-Array":  848.848, "PE glue":   434.601},
    "Bit-Plane-A-BFP":{"DP8-Array": 2904.803, "CPR-Tree": 1874.828,
                     "ACC-Array":  884.831, "PE glue":   378.613},
    "Bit-Plane-B-BFP":{"DP8-Array": 1871.605, "CPR-Tree": 1858.892,
                     "ACC-Array":  884.948, "PE glue":   401.008},
}

FLAT = {"Baseline": 3816.519, "Square": 3320.303, "Baseline-BFP": 5345.990, "Square-BFP": 5204.929,
        "Bit-Plane-B-BFP": 4585.206,
        "Bit-Plane-A-BFP": 5148.898}

VARIANTS = ["Baseline", "Square", "Baseline-BFP", "Square-BFP", "Bit-Plane-A-BFP",
            "Bit-Plane-B-BFP"]
SECTIONS = ["DP8-Array", "CPR-Tree", "ACC-Array", "PE glue"]
CORRESP = {"Square": "Baseline", "Square-BFP": "Baseline-BFP", "Bit-Plane-A-BFP": "Baseline-BFP",
           "Bit-Plane-B-BFP": "Baseline-BFP"}
COLORS = {
    "DP8-Array": "#d4a480cc",
    "CPR-Tree":  "#778d5ecc",
    "ACC-Array": "#9fb3c8cc",
    "PE glue":   "#eadbbccc",
}

def assemble(variant):
    """Measured shares, rescaled to the flat total, normalized to the baseline PE."""
    comps = HIER[variant]
    hier_tot = sum(comps.values())
    scale = FLAT[variant] / hier_tot / FLAT["Baseline"]
    return {s: comps[s] * scale for s in SECTIONS}

PITCH, WIDTH = 0.80, 0.72
SIDE_MARGIN = 0.40
UNITS_PER_IN = 0.74312
AXES_MARGIN_IN = 0.8128

XSPAN = (len(VARIANTS) - 1) * PITCH + WIDTH + 2 * SIDE_MARGIN
FIG_W = XSPAN / UNITS_PER_IN + AXES_MARGIN_IN

bars = [(v, assemble(v)) for v in VARIANTS]
tot = [sum(cat.values()) for _, cat in bars]

x = [bi * PITCH for bi in range(len(VARIANTS))]

fig, ax = plt.subplots(figsize=(FIG_W, 6.0))
width = WIDTH

for xi, (_, cat) in zip(x, bars):
    bottom = 0.0
    for sec in SECTIONS:
        val = cat[sec]
        if val > 0:
            ax.bar(xi, val, width, bottom=bottom, color=COLORS[sec],
                   edgecolor="black", linewidth=0.4, zorder=3)
        bottom += val

pad = 0.012 * max(tot)
total_of = {v: sum(cat.values()) for v, cat in bars}
for (v, _), xi, t_ in zip(bars, x, tot):
    label = f"{t_:.3f}"
    if v in CORRESP:
        label += f"\n({t_ / total_of[CORRESP[v]] - 1.0:+.1%})"
    ax.text(xi, t_ + pad, label, ha="center", va="bottom", fontsize=8.5)

ax.set_xticks(x)
ax.set_xticklabels(VARIANTS, rotation=20, ha="right", fontsize=9)

mid = 0.5 * (x[0] + x[-1])
ax.set_xlim(mid - XSPAN / 2, mid + XSPAN / 2)

ax.set_ylabel("Normalized cell area [Baseline PE = 1]")
ax.set_title("Synthesis Cell Area — Processing Element (ASAP7)")
ax.set_ylim(0, max(tot) * 1.15)
ax.grid(axis="y", linestyle="--", alpha=0.35, zorder=0)

legend = [Patch(facecolor=COLORS[s], edgecolor="black", linewidth=0.4, label=s) for s in SECTIONS]
ax.legend(handles=legend, loc="upper left", frameon=False)

fig.tight_layout()
out = Path(__file__).with_name("hist_syn_pe_area.png")
fig.savefig(out, dpi=200, bbox_inches="tight")
print(f"saved {out}")
for (v, cat), t_ in zip(bars, tot):
    rel = f"  ({t_ / total_of[CORRESP[v]] - 1:+.1%})" if v in CORRESP else ""
    print(f"{v:13s} total={t_:6.3f}{rel:>10}  " +
          "  ".join(f"{s}={cat[s]:.3f}" for s in SECTIONS))
