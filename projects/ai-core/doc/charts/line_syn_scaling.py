# -----------------------------------------------------------------------------
# Author: Simone Machetti
#
# Description:
#   Line charts of the area and dynamic-power gain of each variant against its
#   own baseline as the grid grows - square vs baseline, and square-BFP and
#   bit-plane-A BFP vs baseline-BFP, from 2x2 up to 128x128. The curves are the
#   same instance-count
#   model used by hist_syn_area.py and hist_syn_pwr.py (PE = N^2, dispatch and
#   alpha-beta = N, icg = N^2 + 2N, ctrl/const/glue = 1) evaluated over a range of
#   N instead of at the two fixed sizes, so the 8x8 and 16x16 bars of those charts
#   are two points on these curves by construction. The square trades an N^2
#   per-PE saving against an N per-row/column alpha-beta cost, so each curve
#   starts positive (the square is worse), crosses zero at the crossover N, and
#   converges to the per-PE ratio - the gain with the alpha-beta overhead
#   amortized away. Crossings and asymptotes are annotated. Values are collected
#   in doc/data/res_syn_scaling.xlsx. Writes line_syn_scaling_area.png and
#   line_syn_scaling_pwr.png next to this.
# -----------------------------------------------------------------------------

from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

AREA = {
    "pe": 3816.519, "pe_sqr": 3320.303, "pe_bfp": 5345.990, "pe_sqr_bfp": 5204.929,
    "icg": 0.262, "ctrl": 8.879, "ctrl_sqr": 9.769, "const_sqr": 3.747,
    "const_sqr_bfp": 4.184, "disp_array_a": 277.734, "disp_array_b": 466.327,
    "disp_array_a_sqr": 366.118, "disp_array_b_sqr": 332.686,
    "disp_array_exp_a_bfp": 42.924, "disp_array_exp_b_bfp": 75.174,
    "disp_array_exp_a_sqr_bfp": 41.990, "disp_array_exp_b_sqr_bfp": 68.584,
    "pe_array_alpha_sqr": 1962.235, "pe_array_beta_sqr": 1753.682,
    "pe_array_alpha_sqr_bfp": 1226.688, "pe_array_beta_sqr_bfp": 1070.755,
    "pe_bpl_a_bfp": 5148.898, "disp_array_b_bpl_a_bfp": 616.224,
    "pe_bpl_b_bfp": 4585.206, "disp_array_a_bpl_b_bfp": 397.495,
    "glue_bas": 1.779, "glue_sqr": 20.383, "glue_bfp": 1.779, "glue_sqr_bfp": 3.470,
    "glue_bpl_a_bfp": 4.753, "glue_bpl_b_bfp": 4.755,
}

VAR_AREA = {
    "Baseline": {
        "PE": [("pe", "N2"), ("icg", "N2")], "AB": [],
        "OT": [("disp_array_a", "N"), ("disp_array_b", "N"), ("icg", "2N"),
               ("ctrl", "1"), ("glue_bas", "1")]},
    "Square": {
        "PE": [("pe_sqr", "N2"), ("icg", "N2")],
        "AB": [("pe_array_alpha_sqr", "N"), ("pe_array_beta_sqr", "N")],
        "OT": [("disp_array_a_sqr", "N"), ("disp_array_b_sqr", "N"), ("icg", "2N"),
               ("ctrl_sqr", "1"), ("const_sqr", "1"), ("glue_sqr", "1")]},
    "Baseline-BFP": {
        "PE": [("pe_bfp", "N2"), ("icg", "N2")], "AB": [],
        "OT": [("disp_array_a", "N"), ("disp_array_b", "N"),
               ("disp_array_exp_a_bfp", "N"), ("disp_array_exp_b_bfp", "N"),
               ("icg", "2N"), ("ctrl", "1"), ("glue_bfp", "1")]},
    "Square-BFP": {
        "PE": [("pe_sqr_bfp", "N2"), ("icg", "N2")],
        "AB": [("pe_array_alpha_sqr_bfp", "N"), ("pe_array_beta_sqr_bfp", "N")],
        "OT": [("disp_array_a_sqr", "N"), ("disp_array_b_sqr", "N"),
               ("disp_array_exp_a_sqr_bfp", "N"), ("disp_array_exp_b_sqr_bfp", "N"),
               ("icg", "2N"), ("ctrl_sqr", "1"), ("const_sqr_bfp", "1"),
               ("glue_sqr_bfp", "1")]},
    "Bit-Plane-A-BFP": {
        "PE": [("pe_bpl_a_bfp", "N2"), ("icg", "N2")], "AB": [],
        "OT": [("disp_array_a", "N"), ("disp_array_b_bpl_a_bfp", "N"),
               ("disp_array_exp_a_bfp", "N"), ("disp_array_exp_b_bfp", "N"),
               ("icg", "2N"), ("ctrl", "1"), ("glue_bpl_a_bfp", "1")]},
    "Bit-Plane-B-BFP": {
        "PE": [("pe_bpl_b_bfp", "N2"), ("icg", "N2")], "AB": [],
        "OT": [("disp_array_a_bpl_b_bfp", "N"), ("disp_array_b", "N"),
               ("disp_array_exp_a_bfp", "N"), ("disp_array_exp_b_bfp", "N"),
               ("icg", "2N"), ("ctrl", "1"), ("glue_bpl_b_bfp", "1")]},
}

VAR_PWR = {
    "Baseline": {
        "PE": [(0.68225, "N2"), (0.02080, "N2")], "AB": [],
        "OT": [(0.10100, "N"), (0.09975, "N"), (0.00591, "2N"), (0.00127, "1"), (0.00139, "1")]},
    "Square": {
        "PE": [(0.51700, "N2"), (0.01970, "N2")], "AB": [(0.40000, "N"), (0.36500, "N")],
        "OT": [(0.12300, "N"), (0.10700, "N"), (0.01490, "2N"), (0.00177, "1"),
               (0.00001, "1"), (0.00182, "1")]},
    "Baseline-BFP": {
        "PE": [(0.91850, "N2"), (0.02610, "N2")], "AB": [],
        "OT": [(0.10200, "N"), (0.10100, "N"), (0.01380, "N"), (0.01610, "N"),
               (0.00673, "2N"), (0.00136, "1")]},
    "Square-BFP": {
        "PE": [(0.82000, "N2"), (0.02620, "N2")], "AB": [(0.29050, "N"), (0.27200, "N")],
        "OT": [(0.12250, "N"), (0.10800, "N"), (0.01020, "N"), (0.01665, "N"),
               (0.00673, "2N"), (0.00162, "1"), (0.00002, "1")]},
    "Bit-Plane-A-BFP": {
        "PE": [(0.90700, "N2"), (0.02620, "N2")], "AB": [],
        "OT": [(0.12200, "N"), (0.14850, "N"), (0.01370, "N"), (0.01615, "N"),
               (0.00673, "2N"), (0.00137, "1")]},
    "Bit-Plane-B-BFP": {
        "PE": [(0.77125, "N2"), (0.02620, "N2")], "AB": [],
        "OT": [(0.13200, "N"), (0.11500, "N"), (0.01340, "N"), (0.01610, "N"),
               (0.00673, "2N"), (0.00130, "1")]},
}

PAIRS = [("Square", "Baseline"), ("Square-BFP", "Baseline-BFP"),
         ("Bit-Plane-A-BFP", "Baseline-BFP"), ("Bit-Plane-B-BFP", "Baseline-BFP")]
COLORS = {"Square": "#b5793f", "Square-BFP": "#5a7043", "Bit-Plane-A-BFP": "#4a6d8c",
          "Bit-Plane-B-BFP": "#8c5a7a"}
MARKED = [8, 16]
TICKS = [2, 4, 8, 16, 32, 64, 128]

def mult(k, n):
    return {"1": 1, "N": n, "2N": 2 * n, "N2": n * n}[k]

def total_area(variant, n):
    return sum(AREA[m] * mult(k, n) for sec in VAR_AREA[variant].values() for m, k in sec)

def total_pwr(variant, n):
    return sum(u * mult(k, n) for sec in VAR_PWR[variant].values() for u, k in sec)

def gain(fn, sqr, base, n):
    return fn(sqr, n) / fn(base, n) - 1.0

def asymptote(fn, sqr, base):
    return gain(fn, sqr, base, 10 ** 7)

def crossover(fn, sqr, base):
    lo, hi = 1.0, 400.0
    for _ in range(200):
        mid = 0.5 * (lo + hi)
        if gain(fn, sqr, base, mid) > 0:
            lo = mid
        else:
            hi = mid
    return 0.5 * (lo + hi)

def draw(fn, quantity, unit, fname):
    ns = [2 + 0.25 * i for i in range(int((128 - 2) / 0.25) + 1)]

    fig, ax = plt.subplots(figsize=(11.5, 6.0))
    ax.axhline(0.0, color="black", linewidth=1.0, zorder=2)

    for sqr, base in PAIRS:
        ys = [100.0 * gain(fn, sqr, base, n) for n in ns]
        ax.plot(ns, ys, color=COLORS[sqr], linewidth=2.2, zorder=4,
                label=f"{sqr} vs {base}")

        asy = 100.0 * asymptote(fn, sqr, base)
        ax.axhline(asy, color=COLORS[sqr], linewidth=1.2, linestyle="--", alpha=0.75, zorder=3)
        ax.text(128, asy, f" {asy:+.1f} %", color=COLORS[sqr], fontsize=8.5,
                va="center", ha="left")

        xo = crossover(fn, sqr, base)
        ax.plot([xo], [0.0], marker="o", markersize=6, color=COLORS[sqr],
                markeredgecolor="black", markeredgewidth=0.4, zorder=5)

        for n in MARKED:
            y = 100.0 * gain(fn, sqr, base, n)
            ax.plot([n], [y], marker="s", markersize=5, color=COLORS[sqr],
                    markeredgecolor="black", markeredgewidth=0.4, zorder=5)
            up = y >= 0.0
            ax.annotate(f"{y:+.1f} %", (n, y), textcoords="offset points",
                        xytext=(0, 8 if up else -8), ha="center",
                        va="bottom" if up else "top", fontsize=8)

    ax.set_xscale("log", base=2)
    ax.set_xticks(TICKS)
    ax.set_xticklabels([f"{t}×{t}" for t in TICKS], fontsize=9)
    ax.set_xlim(2, 128)
    ax.minorticks_off()

    ax.set_xlabel("Grid size")
    ax.set_ylabel(f"{quantity} gain vs own baseline [%]")
    ax.set_title(f"{quantity} Scaling — Square vs Baseline and Square-BFP vs Baseline-BFP (ASAP7)")
    ax.grid(axis="y", linestyle="--", alpha=0.35, zorder=0)
    ax.legend(loc="upper right", frameon=False)

    fig.tight_layout()
    out = Path(__file__).with_name(fname)
    fig.savefig(out, dpi=200, bbox_inches="tight")
    print(f"saved {out}")

    for sqr, base in PAIRS:
        xo = crossover(fn, sqr, base)
        asy = 100.0 * asymptote(fn, sqr, base)
        pts = "  ".join(f"{n}:{100.0 * gain(fn, sqr, base, n):+6.1f}" for n in TICKS)
        print(f"{quantity:5s} {sqr:11s} vs {base:13s} crossover N={xo:6.2f}  "
              f"asymptote={asy:+6.1f} %   {pts}   [{unit}]")

draw(total_area, "Area", "um^2", "line_syn_scaling_area.png")
draw(total_pwr, "Power", "mW", "line_syn_scaling_pwr.png")
