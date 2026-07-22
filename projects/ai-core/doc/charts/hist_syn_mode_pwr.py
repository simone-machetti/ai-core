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
        "1": {"PE":     37.97120, "Alpha-Beta":      0.00000, "Dispatch":      1.59920, "Clock":      0.09472, "Others":      0.00064},
        "2": {"PE":     44.62720, "Alpha-Beta":      0.00000, "Dispatch":      1.59720, "Clock":      0.09472, "Others":      0.00141},
        "3": {"PE":     44.56320, "Alpha-Beta":      0.00000, "Dispatch":      1.39720, "Clock":      0.09472, "Others":      0.00158},
        "5": {"PE":     23.28320, "Alpha-Beta":      0.00000, "Dispatch":      1.52680, "Clock":      0.09472, "Others":      0.00132},
        "6": {"PE":     25.41120, "Alpha-Beta":      0.00000, "Dispatch":      1.53200, "Clock":      0.09472, "Others":      0.00160},
        "7": {"PE":     44.14720, "Alpha-Beta":      0.00000, "Dispatch":      1.60240, "Clock":      0.09472, "Others":      0.00180},
        "8": {"PE":     46.46720, "Alpha-Beta":      0.00000, "Dispatch":      1.59680, "Clock":      0.09472, "Others":      0.00186},
        "9": {"PE":     46.93120, "Alpha-Beta":      0.00000, "Dispatch":      1.59680, "Clock":      0.09472, "Others":      0.00181},
        "10": {"PE":     44.86720, "Alpha-Beta":      0.00000, "Dispatch":      1.60960, "Clock":      0.09472, "Others":      0.00157},
        "11": {"PE":     44.64320, "Alpha-Beta":      0.00000, "Dispatch":      1.61280, "Clock":      0.09472, "Others":      0.00174},
        "12": {"PE":     46.80320, "Alpha-Beta":      0.00000, "Dispatch":      1.38880, "Clock":      0.09472, "Others":      0.00170},
    },
    16: {
        "1": {"PE":    151.88480, "Alpha-Beta":      0.00000, "Dispatch":      3.19840, "Clock":      0.18944, "Others":      0.00064},
        "2": {"PE":    178.50880, "Alpha-Beta":      0.00000, "Dispatch":      3.19440, "Clock":      0.18944, "Others":      0.00141},
        "3": {"PE":    178.25280, "Alpha-Beta":      0.00000, "Dispatch":      2.79440, "Clock":      0.18944, "Others":      0.00158},
        "5": {"PE":     93.13280, "Alpha-Beta":      0.00000, "Dispatch":      3.05360, "Clock":      0.18944, "Others":      0.00132},
        "6": {"PE":    101.64480, "Alpha-Beta":      0.00000, "Dispatch":      3.06400, "Clock":      0.18944, "Others":      0.00160},
        "7": {"PE":    176.58880, "Alpha-Beta":      0.00000, "Dispatch":      3.20480, "Clock":      0.18944, "Others":      0.00180},
        "8": {"PE":    185.86880, "Alpha-Beta":      0.00000, "Dispatch":      3.19360, "Clock":      0.18944, "Others":      0.00186},
        "9": {"PE":    187.72480, "Alpha-Beta":      0.00000, "Dispatch":      3.19360, "Clock":      0.18944, "Others":      0.00181},
        "10": {"PE":    179.46880, "Alpha-Beta":      0.00000, "Dispatch":      3.21920, "Clock":      0.18944, "Others":      0.00157},
        "11": {"PE":    178.57280, "Alpha-Beta":      0.00000, "Dispatch":      3.22560, "Clock":      0.18944, "Others":      0.00174},
        "12": {"PE":    187.21280, "Alpha-Beta":      0.00000, "Dispatch":      2.77760, "Clock":      0.18944, "Others":      0.00170},
    },
}

SQUARE = {
    8: {
        "1": {"PE":     35.19680, "Alpha-Beta":      5.52800, "Dispatch":      1.88000, "Clock":      0.23840, "Others":      0.00124},
        "2": {"PE":     35.29280, "Alpha-Beta":      6.22000, "Dispatch":      1.88000, "Clock":      0.23840, "Others":      0.00251},
        "3": {"PE":     38.20480, "Alpha-Beta":      6.70400, "Dispatch":      1.68680, "Clock":      0.23840, "Others":      0.00344},
        "5": {"PE":     18.74880, "Alpha-Beta":      2.90400, "Dispatch":      1.45840, "Clock":      0.23840, "Others":      0.00260},
        "6": {"PE":     17.70880, "Alpha-Beta":      3.07600, "Dispatch":      1.43320, "Clock":      0.23840, "Others":      0.00320},
        "7": {"PE":     36.58880, "Alpha-Beta":      6.91200, "Dispatch":      1.88000, "Clock":      0.23840, "Others":      0.00374},
        "8": {"PE":     35.64480, "Alpha-Beta":      7.21200, "Dispatch":      1.89200, "Clock":      0.23840, "Others":      0.00409},
        "9": {"PE":     37.29280, "Alpha-Beta":      7.12400, "Dispatch":      1.89200, "Clock":      0.23840, "Others":      0.00404},
        "10": {"PE":     36.66880, "Alpha-Beta":      6.42000, "Dispatch":      1.88000, "Clock":      0.23840, "Others":      0.00348},
        "11": {"PE":     35.24480, "Alpha-Beta":      6.59200, "Dispatch":      1.89200, "Clock":      0.23840, "Others":      0.00365},
        "12": {"PE":     37.35680, "Alpha-Beta":      7.11600, "Dispatch":      1.65200, "Clock":      0.23840, "Others":      0.00406},
    },
    16: {
        "1": {"PE":    140.78720, "Alpha-Beta":     11.05600, "Dispatch":      3.76000, "Clock":      0.47680, "Others":      0.00124},
        "2": {"PE":    141.17120, "Alpha-Beta":     12.44000, "Dispatch":      3.76000, "Clock":      0.47680, "Others":      0.00251},
        "3": {"PE":    152.81920, "Alpha-Beta":     13.40800, "Dispatch":      3.37360, "Clock":      0.47680, "Others":      0.00344},
        "5": {"PE":     74.99520, "Alpha-Beta":      5.80800, "Dispatch":      2.91680, "Clock":      0.47680, "Others":      0.00260},
        "6": {"PE":     70.83520, "Alpha-Beta":      6.15200, "Dispatch":      2.86640, "Clock":      0.47680, "Others":      0.00320},
        "7": {"PE":    146.35520, "Alpha-Beta":     13.82400, "Dispatch":      3.76000, "Clock":      0.47680, "Others":      0.00374},
        "8": {"PE":    142.57920, "Alpha-Beta":     14.42400, "Dispatch":      3.78400, "Clock":      0.47680, "Others":      0.00409},
        "9": {"PE":    149.17120, "Alpha-Beta":     14.24800, "Dispatch":      3.78400, "Clock":      0.47680, "Others":      0.00404},
        "10": {"PE":    146.67520, "Alpha-Beta":     12.84000, "Dispatch":      3.76000, "Clock":      0.47680, "Others":      0.00348},
        "11": {"PE":    140.97920, "Alpha-Beta":     13.18400, "Dispatch":      3.78400, "Clock":      0.47680, "Others":      0.00365},
        "12": {"PE":    149.42720, "Alpha-Beta":     14.23200, "Dispatch":      3.30400, "Clock":      0.47680, "Others":      0.00406},
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
