# -----------------------------------------------------------------------------
# Author: Simone Machetti
#
# Description:
#   Bar chart of synthesized cell area at the DOT-PRODUCT level for the five PE
#   variants - baseline (dp_8), square (dp_8_sqr), BFP (dp_8), square-BFP
#   (dp_8_sqr) and bit-plane-A BFP (dp_8_bpl_a_bfp). Scope is the array of 16
#   dot-product cores inside one PE, i.e. the arithmetic core alone, with no
#   reduction tree and no accumulator. Values are the sum of the 16 instances
#   measured inside each PE with the module boundaries preserved
#   (imp/{pe,pe_sqr,pe_bfp,pe_sqr_bfp,pe_bpl_a_bfp}_hier_syn, produced by
#   scripts/run_syn_pe_area.sh); the standalone dp_8 / dp_8_sqr / dp_8_bpl_a_bfp
#   runs cross-check them. Bars are NORMALIZED to the baseline DP8 array so the
#   chart carries the
#   ratio and not the absolute micron figure. The BFP variants reuse the integer
#   core unchanged, so their bars land on their integer counterparts - that is
#   the result, not a plotting artefact. Absolute values are collected in
#   doc/data/res_syn_pe_area.xlsx. Writes hist_syn_dp_area.png next to this.
# -----------------------------------------------------------------------------

from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Patch

AREA = {
    "Baseline":     3059.730,
    "Square":       1892.601,
    "Baseline-BFP": 3091.572,
    "Square-BFP":   1892.601,
    "Bit-Plane-A-BFP":2904.803,
}

VARIANTS = ["Baseline", "Square", "Baseline-BFP", "Square-BFP", "Bit-Plane-A-BFP"]
CORRESP = {"Square": "Baseline", "Square-BFP": "Baseline-BFP", "Bit-Plane-A-BFP": "Baseline-BFP"}
COLORS = {"DP8-Array": "#d4a480cc"}

PITCH, WIDTH = 0.80, 0.72
SIDE_MARGIN = 0.40
UNITS_PER_IN = 0.74312
AXES_MARGIN_IN = 0.8128

XSPAN = (len(VARIANTS) - 1) * PITCH + WIDTH + 2 * SIDE_MARGIN
FIG_W = XSPAN / UNITS_PER_IN + AXES_MARGIN_IN

norm = {v: AREA[v] / AREA["Baseline"] for v in VARIANTS}
tot = [norm[v] for v in VARIANTS]

x = [bi * PITCH for bi in range(len(VARIANTS))]

fig, ax = plt.subplots(figsize=(FIG_W, 6.0))
width = WIDTH

for xi, v in zip(x, VARIANTS):
    ax.bar(xi, norm[v], width, color=COLORS["DP8-Array"],
           edgecolor="black", linewidth=0.4, zorder=3)

pad = 0.012 * max(tot)
for v, xi, t_ in zip(VARIANTS, x, tot):
    label = f"{t_:.3f}"
    if v in CORRESP:
        label += f"\n({t_ / norm[CORRESP[v]] - 1.0:+.1%})"
    ax.text(xi, t_ + pad, label, ha="center", va="bottom", fontsize=8.5)

ax.set_xticks(x)
ax.set_xticklabels(VARIANTS, rotation=20, ha="right", fontsize=9)

mid = 0.5 * (x[0] + x[-1])
ax.set_xlim(mid - XSPAN / 2, mid + XSPAN / 2)

ax.set_ylabel("Normalized cell area [Baseline = 1]")
ax.set_title("Synthesis Cell Area — DP8 Array (ASAP7)")
ax.set_ylim(0, max(tot) * 1.15)
ax.grid(axis="y", linestyle="--", alpha=0.35, zorder=0)

legend = [Patch(facecolor=COLORS["DP8-Array"], edgecolor="black", linewidth=0.4, label="DP8-Array")]
ax.legend(handles=legend, loc="upper left", frameon=False)

fig.tight_layout()
out = Path(__file__).with_name("hist_syn_dp_area.png")
fig.savefig(out, dpi=200, bbox_inches="tight")
print(f"saved {out}")
for v, t_ in zip(VARIANTS, tot):
    rel = f"  ({t_ / norm[CORRESP[v]] - 1:+.1%})" if v in CORRESP else ""
    print(f"{v:13s} norm={t_:6.3f}{rel:>10}   absolute={AREA[v]:9.3f} um^2")
