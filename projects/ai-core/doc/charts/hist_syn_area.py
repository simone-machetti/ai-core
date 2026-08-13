# -----------------------------------------------------------------------------
# Author: Simone Machetti
#
# Description:
#   Stacked-bar chart of synthesized cell area for the five PE-grid variants -
#   baseline (top_NxN), square (top_NxN_sqr), BFP (top_NxN_bfp), square-BFP
#   (top_NxN_sqr_bfp) and bit-plane-A BFP (top_NxN_bpl_a_bfp) - at 8x8 and 16x16,
#   split into PE / Alpha-Beta / Dispatch / Clock (ICG) / Others (matching
#   hist_syn_pwr.py). Every bar is assembled analytically from the per-component
#   standalone cell areas and a per-N count model; the fixed top-level glue is
#   the 2x2 grid area minus the assembled components at N=2. Bars are NORMALIZED
#   to the baseline grid of the same size, so the y axis is a ratio. The unit
#   areas (um^2) and glue are inlined below - only the components and the 2x2
#   grids are ever synthesized, the 8x8 and 16x16 grids are never built. Values
#   are collected in doc/data/res_syn_area.xlsx. Writes hist_syn_area.png next
#   to this.
# -----------------------------------------------------------------------------

from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Patch

AREA = {
    "pe":                      3816.519,
    "pe_sqr":                  3320.303,
    "pe_bfp":                  5345.990,
    "pe_sqr_bfp":              5204.929,
    "pe_bpl_a_bfp":            5148.898,
    "pe_bpl_b_bfp":            4585.206,
    "icg":                        0.262,
    "ctrl":                       8.879,
    "ctrl_sqr":                   9.769,
    "const_sqr":                  3.747,
    "const_sqr_bfp":              4.184,
    "disp_array_a":             277.734,
    "disp_array_b":             466.327,
    "disp_array_b_bpl_a_bfp":   616.224,
    "disp_array_a_bpl_b_bfp":   397.495,
    "disp_array_a_sqr":         366.118,
    "disp_array_b_sqr":         332.686,
    "disp_array_exp_a_bfp":      42.924,
    "disp_array_exp_b_bfp":      75.174,
    "disp_array_exp_a_sqr_bfp":  41.990,
    "disp_array_exp_b_sqr_bfp":  68.584,
    "pe_array_alpha_sqr":      1962.235,
    "pe_array_beta_sqr":       1753.682,
    "pe_array_alpha_sqr_bfp":  1226.688,
    "pe_array_beta_sqr_bfp":   1070.755,
}

GLUE = {"Baseline": 1.779, "Square": 20.383, "Baseline-BFP": 1.779, "Square-BFP": 3.470,
        "Bit-Plane-B-BFP": 4.755,
        "Bit-Plane-A-BFP": 4.753}

VAR = {
    "Baseline": {
        "PE":         [("pe", "N2"), ("icg", "N2")],
        "Alpha-Beta": [],
        "Dispatch":   [("disp_array_a", "N"), ("disp_array_b", "N")],
        "Clock":      [("icg", "2N")],
        "Others":     [("ctrl", "1")]},
    "Square": {
        "PE":         [("pe_sqr", "N2"), ("icg", "N2")],
        "Alpha-Beta": [("pe_array_alpha_sqr", "N"), ("pe_array_beta_sqr", "N")],
        "Dispatch":   [("disp_array_a_sqr", "N"), ("disp_array_b_sqr", "N")],
        "Clock":      [("icg", "2N")],
        "Others":     [("ctrl_sqr", "1"), ("const_sqr", "1")]},
    "Baseline-BFP": {
        "PE":         [("pe_bfp", "N2"), ("icg", "N2")],
        "Alpha-Beta": [],
        "Dispatch":   [("disp_array_a", "N"), ("disp_array_b", "N"),
                       ("disp_array_exp_a_bfp", "N"), ("disp_array_exp_b_bfp", "N")],
        "Clock":      [("icg", "2N")],
        "Others":     [("ctrl", "1")]},
    "Square-BFP": {
        "PE":         [("pe_sqr_bfp", "N2"), ("icg", "N2")],
        "Alpha-Beta": [("pe_array_alpha_sqr_bfp", "N"), ("pe_array_beta_sqr_bfp", "N")],
        "Dispatch":   [("disp_array_a_sqr", "N"), ("disp_array_b_sqr", "N"),
                       ("disp_array_exp_a_sqr_bfp", "N"), ("disp_array_exp_b_sqr_bfp", "N")],
        "Clock":      [("icg", "2N")],
        "Others":     [("ctrl_sqr", "1"), ("const_sqr_bfp", "1")]},
    "Bit-Plane-A-BFP": {
        "PE":         [("pe_bpl_a_bfp", "N2"), ("icg", "N2")],
        "Alpha-Beta": [],
        "Dispatch":   [("disp_array_a", "N"), ("disp_array_b_bpl_a_bfp", "N"),
                       ("disp_array_exp_a_bfp", "N"), ("disp_array_exp_b_bfp", "N")],
        "Clock":      [("icg", "2N")],
        "Others":     [("ctrl", "1")]},
    "Bit-Plane-B-BFP": {
        "PE":         [("pe_bpl_b_bfp", "N2"), ("icg", "N2")],
        "Alpha-Beta": [],
        "Dispatch":   [("disp_array_a_bpl_b_bfp", "N"), ("disp_array_b", "N"),
                       ("disp_array_exp_a_bfp", "N"), ("disp_array_exp_b_bfp", "N")],
        "Clock":      [("icg", "2N")],
        "Others":     [("ctrl", "1")]},
    }

VARIANTS = ["Baseline", "Square", "Baseline-BFP", "Square-BFP", "Bit-Plane-A-BFP",
            "Bit-Plane-B-BFP"]
SECTIONS = ["PE", "Alpha-Beta", "Dispatch", "Clock", "Others"]

def mult(k, n):
    return {"1": 1, "N": n, "2N": 2 * n, "N2": n * n}[k]

def assemble(variant, n):
    out = {}
    for s in SECTIONS:
        tot = sum(AREA[m] * mult(k, n) for m, k in VAR[variant][s])
        if s == "Others":
            tot += GLUE[variant] * mult("1", n)
        out[s] = tot
    return out

COLORS = {
    "PE":         "#d4a480cc",
    "Dispatch":   "#ced4da",
    "Alpha-Beta": "#778d5ecc",
    "Clock":      "#9fb3c8cc",
    "Others":     "#eadbbccc",
}

SIZES = [8, 16]

base_tot = {sz: sum(assemble("Baseline", sz).values()) for sz in SIZES}
bars = [(v, sz, {s: a / base_tot[sz] for s, a in assemble(v, sz).items()})
        for sz in SIZES for v in VARIANTS]
tot = [sum(cat.values()) for _, _, cat in bars]

x = []
x0 = 0.0
for _ in SIZES:
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
           "Bit-Plane-A-BFP": "Baseline-BFP", "Bit-Plane-B-BFP": "Baseline-BFP"}
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

ax.set_ylabel("Normalized cell area [Baseline = 1]")
ax.set_title(f"Synthesis Cell Area — {' / '.join(VARIANTS)} Matrix Grid (ASAP7)")
ax.set_ylim(0, max(tot) * 1.15)
ax.grid(axis="y", linestyle="--", alpha=0.35, zorder=0)

legend = [Patch(facecolor=COLORS[s], edgecolor="black", linewidth=0.4, label=s) for s in SECTIONS]
ax.legend(handles=legend, loc="upper left", frameon=False)

fig.tight_layout()
out = Path(__file__).with_name("hist_syn_area.png")
fig.savefig(out, dpi=200, bbox_inches="tight")
print(f"saved {out}")
for (v, sz, cat), t_ in zip(bars, tot):
    rel = f"  ({t_ / total_of[(CORRESP[v], sz)] - 1:+.1%})" if v in CORRESP else ""
    print(f"{v:11s} {sz:2d}x{sz:<2d} total={t_:6.3f}{rel:>10}  " +
          "  ".join(f"{s}={cat[s]:.3f}" for s in SECTIONS))
