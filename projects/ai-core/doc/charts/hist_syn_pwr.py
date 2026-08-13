# -----------------------------------------------------------------------------
# Author: Simone Machetti
#
# Description:
#   Stacked-bar chart of VCD-annotated dynamic power for the five PE-grid
#   variants - baseline (top_NxN), square (top_NxN_sqr), BFP (top_NxN_bfp),
#   square-BFP (top_NxN_sqr_bfp) and bit-plane-A BFP (top_NxN_bpl_a_bfp) - at 8x8
#   and 16x16, split into PE / Alpha-Beta / Dispatch / Clock (ICG) / Others.
#   Every bar is assembled from the per-component unit powers measured on the
#   complete 2x2 grids at 100 vectors (imp/dpa_2x2*/report/power_hierarchy.rpt)
#   - gate-level simulation of an 8x8 or 16x16 grid does not fit in memory - and
#   collected per category in doc/data/res_syn_pwr.xlsx. All five variants come
#   from the same VCD-annotated run set so they are mutually consistent. Bars
#   are NORMALIZED to the baseline grid of the same size. Colours follow
#   hist_syn_area.py, with Clock added (power has a clock term area does not).
#   Writes hist_syn_pwr.png next to this.
# -----------------------------------------------------------------------------

from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Patch

UNIT = {
    "Baseline": {
        "PE":         {"pe":         0.68225, "icg_pe": 0.02080},
        "Dispatch":   {"disp_a":     0.10100, "disp_b": 0.09975},
        "Alpha-Beta": {},
        "Clock":      {"icg_rowcol": 0.00591},
        "Others":     {"ctrl":       0.00127, "glue":   0.00139},
    },
    "Square": {
        "PE":         {"pe_sqr":     0.51700, "icg_pe": 0.01970},
        "Dispatch":   {"disp_a_sqr": 0.12300, "disp_b_sqr": 0.10700},
        "Alpha-Beta": {"alpha":      0.40000, "beta":   0.36500},
        "Clock":      {"icg_rowcol": 0.01490},
        "Others":     {"ctrl_sqr":   0.00177, "const_sqr": 0.00001, "glue": 0.00182},
    },
    "Baseline-BFP": {
        "PE":         {"pe_bfp":     0.91850, "icg_pe": 0.02610},
        "Dispatch":   {"disp_a":     0.10200, "disp_b": 0.10100,
                       "disp_exp_a": 0.01380, "disp_exp_b": 0.01610},
        "Alpha-Beta": {},
        "Clock":      {"icg_rowcol": 0.00673},
        "Others":     {"ctrl":       0.00136, "glue":   0.00000},
    },
    "Square-BFP": {
        "PE":         {"pe_sqr_bfp": 0.82000, "icg_pe": 0.02620},
        "Dispatch":   {"disp_a_sqr": 0.12250, "disp_b_sqr": 0.10800,
                       "disp_exp_a": 0.01020, "disp_exp_b": 0.01665},
        "Alpha-Beta": {"alpha":      0.29050, "beta":   0.27200},
        "Clock":      {"icg_rowcol": 0.00673},
        "Others":     {"ctrl_sqr":   0.00162, "const_sqr_bfp": 0.00002, "glue": 0.00000},
    },
    "Bit-Plane-A-BFP": {
        "PE":         {"pe_bpl_a_bfp": 0.90700, "icg_pe": 0.02620},
        "Dispatch":   {"disp_a":     0.12200, "disp_b_bpl": 0.14850,
                       "disp_exp_a": 0.01370, "disp_exp_b": 0.01615},
        "Alpha-Beta": {},
        "Clock":      {"icg_rowcol": 0.00673},
        "Others":     {"ctrl":       0.00137, "glue":   0.00000},
    },
    "Bit-Plane-B-BFP": {
        "PE":         {"pe_bpl_b_bfp": 0.77125, "icg_pe": 0.02620},
        "Dispatch":   {"disp_a_bpl": 0.13200, "disp_b":     0.11500,
                       "disp_exp_a": 0.01340, "disp_exp_b": 0.01610},
        "Alpha-Beta": {},
        "Clock":      {"icg_rowcol": 0.00673},
        "Others":     {"ctrl":       0.00130, "glue":   0.00000},
    },
}

COUNT = {
    "pe": "N2", "pe_sqr": "N2", "pe_bfp": "N2", "pe_sqr_bfp": "N2",
    "pe_bpl_a_bfp": "N2", "pe_bpl_b_bfp": "N2", "icg_pe": "N2",
    "disp_a": "N", "disp_b": "N", "disp_a_sqr": "N", "disp_b_sqr": "N",
    "disp_b_bpl": "N", "disp_a_bpl": "N",
    "disp_exp_a": "N", "disp_exp_b": "N",
    "alpha": "N", "beta": "N", "icg_rowcol": "2N",
    "ctrl": "1", "ctrl_sqr": "1", "const_sqr": "1", "const_sqr_bfp": "1", "glue": "1",
}

VARIANTS = ["Baseline", "Square", "Baseline-BFP", "Square-BFP", "Bit-Plane-A-BFP",
            "Bit-Plane-B-BFP"]

def assemble(variant, n):
    mult = {"1": 1, "N": n, "2N": 2 * n, "N2": n * n}
    return {sec: sum(v * mult[COUNT[k]] for k, v in comps.items())
            for sec, comps in UNIT[variant].items()}

SECTIONS = ["PE", "Alpha-Beta", "Dispatch", "Clock", "Others"]
COLORS = {
    "PE":         "#d4a480cc",
    "Dispatch":   "#ced4da",
    "Alpha-Beta": "#778d5ecc",
    "Clock":      "#9fb3c8cc",
    "Others":     "#eadbbccc",
}

SIZES = [8, 16]

base_tot = {sz: sum(assemble("Baseline", sz).values()) for sz in SIZES}
bars = [(v, sz, {s: p / base_tot[sz] for s, p in assemble(v, sz).items()})
        for sz in SIZES for v in VARIANTS]
tot = [sum(cat.values()) for _, _, cat in bars]

x = []
x0 = 0.0
for gi in range(len(SIZES)):
    for bi in range(len(VARIANTS)):
        x.append(x0 + bi * 0.80)
    x0 += len(VARIANTS) * 0.80 + 0.90

fig, ax = plt.subplots(figsize=(11.5, 6.0))
width = 0.72

for xi, (_, _, cat) in zip(x, bars):
    bottom = 0.0
    for sec in SECTIONS:
        val = cat[sec]
        if val > 0:
            ax.bar(xi, val, width, bottom=bottom, color=COLORS[sec],
                   edgecolor="black", linewidth=0.4, zorder=3)
        bottom += val

pad = 0.012 * max(tot)
CORRESP = {"Square": "Baseline", "Square-BFP": "Baseline-BFP",
           "Bit-Plane-A-BFP": "Baseline-BFP",
           "Bit-Plane-B-BFP": "Baseline-BFP"}
total_of = {(v, sz): sum(cat.values()) for v, sz, cat in bars}
for (v, sz, _), xi, t_ in zip(bars, x, tot):
    label = f"{t_:.3f}"
    if v in CORRESP:
        label += f"\n({t_ / total_of[(CORRESP[v], sz)] - 1.0:+.0%})"
    ax.text(xi, t_ + pad, label, ha="center", va="bottom", fontsize=8.5)

ax.set_xticks(x)
ax.set_xticklabels([b[0] for b in bars], rotation=20, ha="right", fontsize=9)

for gi, sz in enumerate(SIZES):
    xs = x[gi * len(VARIANTS):(gi + 1) * len(VARIANTS)]
    ax.text(sum(xs) / len(xs), -0.14 * max(tot), f"{sz}×{sz}",
            ha="center", va="top", fontsize=11, fontweight="bold")

ax.set_ylabel("Normalized dynamic power [Baseline = 1]")
ax.set_title(f"Dynamic Power — {' / '.join(VARIANTS)} Matrix Grid (ASAP7)")
ax.set_ylim(0, max(tot) * 1.15)
ax.grid(axis="y", linestyle="--", alpha=0.35, zorder=0)

legend = [Patch(facecolor=COLORS[s], edgecolor="black", linewidth=0.4, label=s) for s in SECTIONS]
ax.legend(handles=legend, loc="upper left", frameon=False)

fig.tight_layout()
out = Path(__file__).with_name("hist_syn_pwr.png")
fig.savefig(out, dpi=200, bbox_inches="tight")
print(f"saved {out}")
for (v, sz, cat), t_ in zip(bars, tot):
    rel = f"  ({t_ / total_of[(CORRESP[v], sz)] - 1:+.1%})" if v in CORRESP else ""
    print(f"{v:11s} {sz:2d}x{sz:<2d} total={t_:6.3f}{rel:>10}  " +
          "  ".join(f"{s}={cat[s]:.3f}" for s in SECTIONS))
