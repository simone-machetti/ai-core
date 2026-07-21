# -----------------------------------------------------------------------------
# Author: Simone Machetti
#
# Description:
#   Grouped stacked-bar charts of VCD-annotated dynamic power per operating mode
#   for the baseline (top_NxN) and square (top_NxN_sqr) PE grids, at 8x8 and
#   16x16, split into PE / Alpha-Beta / Dispatch / Clock (ICG) / Others. Two bars
#   per mode, baseline then square, with the square's delta printed above it.
#   Every figure is assembled from per-component unit power measured on the
#   complete 2x2 grids, one gate-level run per mode with 100 random operand sets
#   (imp/dpa_mode_2x2[_sqr]_m<M>/report/power_hierarchy.rpt) - gate-level
#   simulation of an 8x8 or 16x16 grid does not fit in memory. Values in
#   doc/data/res_syn_mode_pwr.xlsx. Colours follow hist_syn_pwr.py. Writes
#   hist_syn_mode_pwr_8x8.png and hist_syn_mode_pwr_16x16.png next to this.
# -----------------------------------------------------------------------------

from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Patch

MODES = [1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12]

BASELINE = {
    8: {
        "1": {"PE":     39.95520, "Alpha-Beta":      0.00000, "Dispatch":      1.60800, "Clock":      0.09472, "Others":      0.00063},
        "2": {"PE":     45.81120, "Alpha-Beta":      0.00000, "Dispatch":      1.60160, "Clock":      0.09472, "Others":      0.00124},
        "3": {"PE":     45.49120, "Alpha-Beta":      0.00000, "Dispatch":      1.40200, "Clock":      0.09472, "Others":      0.00142},
        "5": {"PE":     23.25120, "Alpha-Beta":      0.00000, "Dispatch":      1.53240, "Clock":      0.09472, "Others":      0.00104},
        "6": {"PE":     25.21920, "Alpha-Beta":      0.00000, "Dispatch":      1.53680, "Clock":      0.09472, "Others":      0.00134},
        "7": {"PE":     44.01920, "Alpha-Beta":      0.00000, "Dispatch":      1.60640, "Clock":      0.09472, "Others":      0.00159},
        "8": {"PE":     46.01920, "Alpha-Beta":      0.00000, "Dispatch":      1.59960, "Clock":      0.09472, "Others":      0.00165},
        "9": {"PE":     46.85120, "Alpha-Beta":      0.00000, "Dispatch":      1.59960, "Clock":      0.09472, "Others":      0.00164},
        "10": {"PE":     46.14720, "Alpha-Beta":      0.00000, "Dispatch":      1.61440, "Clock":      0.09472, "Others":      0.00140},
        "11": {"PE":     44.65920, "Alpha-Beta":      0.00000, "Dispatch":      1.62160, "Clock":      0.09472, "Others":      0.00152},
        "12": {"PE":     46.72320, "Alpha-Beta":      0.00000, "Dispatch":      1.39240, "Clock":      0.09472, "Others":      0.00153},
    },
    16: {
        "1": {"PE":    159.82080, "Alpha-Beta":      0.00000, "Dispatch":      3.21600, "Clock":      0.18944, "Others":      0.00063},
        "2": {"PE":    183.24480, "Alpha-Beta":      0.00000, "Dispatch":      3.20320, "Clock":      0.18944, "Others":      0.00124},
        "3": {"PE":    181.96480, "Alpha-Beta":      0.00000, "Dispatch":      2.80400, "Clock":      0.18944, "Others":      0.00142},
        "5": {"PE":     93.00480, "Alpha-Beta":      0.00000, "Dispatch":      3.06480, "Clock":      0.18944, "Others":      0.00104},
        "6": {"PE":    100.87680, "Alpha-Beta":      0.00000, "Dispatch":      3.07360, "Clock":      0.18944, "Others":      0.00134},
        "7": {"PE":    176.07680, "Alpha-Beta":      0.00000, "Dispatch":      3.21280, "Clock":      0.18944, "Others":      0.00159},
        "8": {"PE":    184.07680, "Alpha-Beta":      0.00000, "Dispatch":      3.19920, "Clock":      0.18944, "Others":      0.00165},
        "9": {"PE":    187.40480, "Alpha-Beta":      0.00000, "Dispatch":      3.19920, "Clock":      0.18944, "Others":      0.00164},
        "10": {"PE":    184.58880, "Alpha-Beta":      0.00000, "Dispatch":      3.22880, "Clock":      0.18944, "Others":      0.00140},
        "11": {"PE":    178.63680, "Alpha-Beta":      0.00000, "Dispatch":      3.24320, "Clock":      0.18944, "Others":      0.00152},
        "12": {"PE":    186.89280, "Alpha-Beta":      0.00000, "Dispatch":      2.78480, "Clock":      0.18944, "Others":      0.00153},
    },
}

SQUARE = {
    8: {
        "1": {"PE":     36.78080, "Alpha-Beta":      5.45600, "Dispatch":      1.87600, "Clock":      0.23840, "Others":      0.00124},
        "2": {"PE":     35.22880, "Alpha-Beta":      5.80800, "Dispatch":      1.86800, "Clock":      0.23840, "Others":      0.00224},
        "3": {"PE":     38.20480, "Alpha-Beta":      6.34000, "Dispatch":      1.67480, "Clock":      0.23840, "Others":      0.00317},
        "5": {"PE":     18.44480, "Alpha-Beta":      2.74800, "Dispatch":      1.44440, "Clock":      0.23840, "Others":      0.00217},
        "6": {"PE":     17.32480, "Alpha-Beta":      2.92400, "Dispatch":      1.43080, "Clock":      0.23840, "Others":      0.00280},
        "7": {"PE":     35.37280, "Alpha-Beta":      6.33200, "Dispatch":      1.86800, "Clock":      0.23840, "Others":      0.00337},
        "8": {"PE":     34.06080, "Alpha-Beta":      6.55200, "Dispatch":      1.87600, "Clock":      0.23840, "Others":      0.00369},
        "9": {"PE":     36.04480, "Alpha-Beta":      6.56800, "Dispatch":      1.87600, "Clock":      0.23840, "Others":      0.00368},
        "10": {"PE":     36.54080, "Alpha-Beta":      6.03200, "Dispatch":      1.86800, "Clock":      0.23840, "Others":      0.00320},
        "11": {"PE":     34.18880, "Alpha-Beta":      6.03600, "Dispatch":      1.88000, "Clock":      0.23840, "Others":      0.00328},
        "12": {"PE":     36.10880, "Alpha-Beta":      6.55200, "Dispatch":      1.64120, "Clock":      0.23840, "Others":      0.00369},
    },
    16: {
        "1": {"PE":    147.12320, "Alpha-Beta":     10.91200, "Dispatch":      3.75200, "Clock":      0.47680, "Others":      0.00124},
        "2": {"PE":    140.91520, "Alpha-Beta":     11.61600, "Dispatch":      3.73600, "Clock":      0.47680, "Others":      0.00224},
        "3": {"PE":    152.81920, "Alpha-Beta":     12.68000, "Dispatch":      3.34960, "Clock":      0.47680, "Others":      0.00317},
        "5": {"PE":     73.77920, "Alpha-Beta":      5.49600, "Dispatch":      2.88880, "Clock":      0.47680, "Others":      0.00217},
        "6": {"PE":     69.29920, "Alpha-Beta":      5.84800, "Dispatch":      2.86160, "Clock":      0.47680, "Others":      0.00280},
        "7": {"PE":    141.49120, "Alpha-Beta":     12.66400, "Dispatch":      3.73600, "Clock":      0.47680, "Others":      0.00337},
        "8": {"PE":    136.24320, "Alpha-Beta":     13.10400, "Dispatch":      3.75200, "Clock":      0.47680, "Others":      0.00369},
        "9": {"PE":    144.17920, "Alpha-Beta":     13.13600, "Dispatch":      3.75200, "Clock":      0.47680, "Others":      0.00368},
        "10": {"PE":    146.16320, "Alpha-Beta":     12.06400, "Dispatch":      3.73600, "Clock":      0.47680, "Others":      0.00320},
        "11": {"PE":    136.75520, "Alpha-Beta":     12.07200, "Dispatch":      3.76000, "Clock":      0.47680, "Others":      0.00328},
        "12": {"PE":    144.43520, "Alpha-Beta":     13.10400, "Dispatch":      3.28240, "Clock":      0.47680, "Others":      0.00369},
    },
}

SECTIONS = ["PE", "Alpha-Beta", "Dispatch", "Clock", "Others"]
COLORS = {
    "PE":         "#d4a480cc",
    "Dispatch":   "#ced4da",
    "Alpha-Beta": "#778d5ecc",
    "Clock":      "#9fb3c8cc",
    "Others":     "#eadbbccc",
}

width = 0.38


def draw(n):
    fig, ax = plt.subplots(figsize=(12.0, 5.6))
    tb, ts = [], []
    for i, m in enumerate(MODES):
        for off, data, store in ((-width / 2 - 0.02, BASELINE, tb),
                                 (+width / 2 + 0.02, SQUARE, ts)):
            bottom = 0.0
            for sec in SECTIONS:
                val = data[n][str(m)][sec]
                if val > 0:
                    ax.bar(i + off, val, width, bottom=bottom, color=COLORS[sec],
                           edgecolor="black", linewidth=0.4, zorder=3)
                bottom += val
            store.append(bottom)

    pad = 0.012 * max(ts + tb)
    for i, (b, s) in enumerate(zip(tb, ts)):
        ax.text(i + width / 2 + 0.02, s + pad, f"{s / b - 1.0:+.1%}",
                ha="center", va="bottom", fontsize=7.5)

    ax.set_xticks(range(len(MODES)))
    ax.set_xticklabels([f"mode {m}" for m in MODES], fontsize=9)
    ax.set_xlim(-0.7, len(MODES) - 0.3)
    ax.set_ylabel("Dynamic power [mW]")
    ax.set_title(f"Per-Mode Dynamic Power — Baseline vs Square, {n}x{n} Grid (ASAP7)")
    ax.set_ylim(0, max(ts + tb) * 1.14)
    ax.grid(axis="y", linestyle="--", alpha=0.35, zorder=0)

    legend = [Patch(facecolor=COLORS[s], edgecolor="black", linewidth=0.4, label=s)
              for s in SECTIONS]
    ax.legend(handles=legend, loc="upper left", frameon=False, ncol=5, fontsize=9)

    fig.tight_layout()
    out = Path(__file__).with_name(f"hist_syn_mode_pwr_{n}x{n}.png")
    fig.savefig(out, dpi=200, bbox_inches="tight")
    print(f"saved {out}")
    for m, b, s in zip(MODES, tb, ts):
        print(f"  mode {m:2}  baseline={b:9.3f}  square={s:9.3f}  ratio={s / b:.4f}")


for n in (8, 16):
    draw(n)
