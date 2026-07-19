# -----------------------------------------------------------------------------
# Author: Simone Machetti
#
# Description:
#   Stacked-bar chart of synthesized cell area for the baseline (top_NxN) and
#   square (top_NxN_sqr) PE grids at 8x8 and 16x16, split into PE / Dispatch /
#   Alpha-Beta / Others. Per-component unit areas are the synthesized ASAP7
#   values from doc/data/res_syn_area.xlsx, assembled by instance count
#   (shared x1, per-row/col xN, per-PE xN^2). Colours are taken from the legacy
#   area_ai_core_level_16.png generator. Writes hist_syn_area.png next to this.
# -----------------------------------------------------------------------------

from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Patch

PE_BAS     = 3758.942700
PE_SQR     = 3264.184980
DISP_A     =  348.680700
DISP_B     =  502.485120
DISP_A_SQR =  394.782660
DISP_B_SQR =  349.599240
ALPHA      = 1890.267840
BETA       = 1699.809300
CTRL       =    9.229140
CTRL_SQR   =    9.462420
CONST_SQR  =    4.067820
A_DFF      =    0.379080
TOPREG_BAS =  2 * A_DFF
TOPREG_SQR = 46 * A_DFF


def baseline(n):
    return {
        "PE":         n * n * PE_BAS,
        "Dispatch":   n * (DISP_A + DISP_B),
        "Alpha-Beta": 0.0,
        "Others":     CTRL + TOPREG_BAS,
    }


def square(n):
    return {
        "PE":         n * n * PE_SQR,
        "Dispatch":   n * (DISP_A_SQR + DISP_B_SQR),
        "Alpha-Beta": n * (ALPHA + BETA),
        "Others":     CTRL_SQR + CONST_SQR + TOPREG_SQR,
    }


bars = [
    ("Baseline 8×8",   baseline(8)),
    ("Square 8×8",     square(8)),
    ("Baseline 16×16", baseline(16)),
    ("Square 16×16",   square(16)),
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
