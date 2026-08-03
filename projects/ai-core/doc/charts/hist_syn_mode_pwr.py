# -----------------------------------------------------------------------------
# Author: Simone Machetti
#
# Description:
#   Grouped stacked-bar charts of VCD-annotated dynamic power per operating mode
#   for the four PE-grid variants - baseline (top_NxN), square (top_NxN_sqr), BFP
#   (top_NxN_bfp) and square-BFP (top_NxN_sqr_bfp) - at 8x8 and 16x16, split into
#   PE / Alpha-Beta / Dispatch / Clock (ICG) / Others. Four bars per mode; each
#   non-baseline bar prints its delta vs the same-mode baseline. Every figure is
#   assembled from per-component unit power measured on the complete 2x2 grids, one
#   gate-level run per mode with 100 random operand sets. Values are inlined in
#   DATA below and collected in doc/data/res_syn_mode_pwr.xlsx. Colours follow
#   hist_syn_pwr.py. Writes hist_syn_mode_pwr_8x8.png and _16x16.png.
# -----------------------------------------------------------------------------

from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Patch

MODES = [1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12]
VARIANTS = ["Baseline", "Square", "Baseline-BFP", "Square-BFP"]
SECTIONS = ["PE", "Alpha-Beta", "Dispatch", "Clock", "Others"]
COLORS = {
    "PE":         "#d4a480cc",
    "Dispatch":   "#ced4da",
    "Alpha-Beta": "#778d5ecc",
    "Clock":      "#9fb3c8cc",
    "Others":     "#eadbbccc",
}

DATA = {"Baseline": {"8": {"1": {"PE": 41.1552,"Alpha-Beta": 0.0,"Dispatch": 1.606,"Clock": 0.09472,"Others": 0.00262},"2": {"PE": 47.8752,"Alpha-Beta": 0.0,"Dispatch": 1.6,"Clock": 0.09472,"Others": 0.00412},"3": {"PE": 47.8272,"Alpha-Beta": 0.0,"Dispatch": 1.4268,"Clock": 0.09472,"Others": 0.00166},"5": {"PE": 25.5232,"Alpha-Beta": 0.0,"Dispatch": 1.5228,"Clock": 0.09472,"Others": 0.00141},"6": {"PE": 27.6352,"Alpha-Beta": 0.0,"Dispatch": 1.5692,"Clock": 0.09472,"Others": 0.00165},"7": {"PE": 47.4112,"Alpha-Beta": 0.0,"Dispatch": 1.596,"Clock": 0.09472,"Others": 0.00412},"8": {"PE": 49.7472,"Alpha-Beta": 0.0,"Dispatch": 1.6008,"Clock": 0.09472,"Others": 0.00692},"9": {"PE": 50.2112,"Alpha-Beta": 0.0,"Dispatch": 1.6012,"Clock": 0.09472,"Others": 0.00191},"10": {"PE": 48.1312,"Alpha-Beta": 0.0,"Dispatch": 1.608,"Clock": 0.09472,"Others": 0.00612},"11": {"PE": 47.9072,"Alpha-Beta": 0.0,"Dispatch": 1.6028,"Clock": 0.09472,"Others": 0.00184},"12": {"PE": 50.0512,"Alpha-Beta": 0.0,"Dispatch": 1.3876,"Clock": 0.09472,"Others": 0.00183}},"16": {"1": {"PE": 164.6208,"Alpha-Beta": 0.0,"Dispatch": 3.212,"Clock": 0.18944,"Others": 0.00262},"2": {"PE": 191.5008,"Alpha-Beta": 0.0,"Dispatch": 3.2,"Clock": 0.18944,"Others": 0.00412},"3": {"PE": 191.3088,"Alpha-Beta": 0.0,"Dispatch": 2.8536,"Clock": 0.18944,"Others": 0.00166},"5": {"PE": 102.0928,"Alpha-Beta": 0.0,"Dispatch": 3.0456,"Clock": 0.18944,"Others": 0.00141},"6": {"PE": 110.5408,"Alpha-Beta": 0.0,"Dispatch": 3.1384,"Clock": 0.18944,"Others": 0.00165},"7": {"PE": 189.6448,"Alpha-Beta": 0.0,"Dispatch": 3.192,"Clock": 0.18944,"Others": 0.00412},"8": {"PE": 198.9888,"Alpha-Beta": 0.0,"Dispatch": 3.2016,"Clock": 0.18944,"Others": 0.00692},"9": {"PE": 200.8448,"Alpha-Beta": 0.0,"Dispatch": 3.2024,"Clock": 0.18944,"Others": 0.00191},"10": {"PE": 192.5248,"Alpha-Beta": 0.0,"Dispatch": 3.216,"Clock": 0.18944,"Others": 0.00612},"11": {"PE": 191.6288,"Alpha-Beta": 0.0,"Dispatch": 3.2056,"Clock": 0.18944,"Others": 0.00184},"12": {"PE": 200.2048,"Alpha-Beta": 0.0,"Dispatch": 2.7752,"Clock": 0.18944,"Others": 0.00183}}},"Square": {"8": {"1": {"PE": 35.8208,"Alpha-Beta": 5.52,"Dispatch": 1.896,"Clock": 0.2384,"Others": 0.00091},"2": {"PE": 35.8528,"Alpha-Beta": 6.216,"Dispatch": 1.88,"Clock": 0.2384,"Others": 0.0056},"3": {"PE": 38.7328,"Alpha-Beta": 6.696,"Dispatch": 1.684,"Clock": 0.2384,"Others": 0.0046},"5": {"PE": 19.0528,"Alpha-Beta": 2.904,"Dispatch": 1.468,"Clock": 0.2384,"Others": 0.0066},"6": {"PE": 17.9648,"Alpha-Beta": 3.068,"Dispatch": 1.4504,"Clock": 0.2384,"Others": 0.008},"7": {"PE": 37.1488,"Alpha-Beta": 6.908,"Dispatch": 1.88,"Clock": 0.2384,"Others": 0.0025},"8": {"PE": 36.1888,"Alpha-Beta": 7.204,"Dispatch": 1.88,"Clock": 0.2384,"Others": 0.0076},"9": {"PE": 37.8688,"Alpha-Beta": 7.116,"Dispatch": 1.88,"Clock": 0.2384,"Others": 0.0046},"10": {"PE": 37.2128,"Alpha-Beta": 6.416,"Dispatch": 1.876,"Clock": 0.2384,"Others": 0.00235},"11": {"PE": 35.7888,"Alpha-Beta": 6.588,"Dispatch": 1.888,"Clock": 0.2384,"Others": 0.0046},"12": {"PE": 37.9008,"Alpha-Beta": 7.116,"Dispatch": 1.6584,"Clock": 0.2384,"Others": 0.008}},"16": {"1": {"PE": 143.2832,"Alpha-Beta": 11.04,"Dispatch": 3.792,"Clock": 0.4768,"Others": 0.00091},"2": {"PE": 143.4112,"Alpha-Beta": 12.432,"Dispatch": 3.76,"Clock": 0.4768,"Others": 0.0056},"3": {"PE": 154.9312,"Alpha-Beta": 13.392,"Dispatch": 3.368,"Clock": 0.4768,"Others": 0.0046},"5": {"PE": 76.2112,"Alpha-Beta": 5.808,"Dispatch": 2.936,"Clock": 0.4768,"Others": 0.0066},"6": {"PE": 71.8592,"Alpha-Beta": 6.136,"Dispatch": 2.9008,"Clock": 0.4768,"Others": 0.008},"7": {"PE": 148.5952,"Alpha-Beta": 13.816,"Dispatch": 3.76,"Clock": 0.4768,"Others": 0.0025},"8": {"PE": 144.7552,"Alpha-Beta": 14.408,"Dispatch": 3.76,"Clock": 0.4768,"Others": 0.0076},"9": {"PE": 151.4752,"Alpha-Beta": 14.232,"Dispatch": 3.76,"Clock": 0.4768,"Others": 0.0046},"10": {"PE": 148.8512,"Alpha-Beta": 12.832,"Dispatch": 3.752,"Clock": 0.4768,"Others": 0.00235},"11": {"PE": 143.1552,"Alpha-Beta": 13.176,"Dispatch": 3.776,"Clock": 0.4768,"Others": 0.0046},"12": {"PE": 151.6032,"Alpha-Beta": 14.232,"Dispatch": 3.3168,"Clock": 0.4768,"Others": 0.008}}},"Baseline-BFP": {"8": {"1": {"PE": 57.6224,"Alpha-Beta": 0.0,"Dispatch": 1.8644,"Clock": 0.10784,"Others": 0.00084},"2": {"PE": 65.6544,"Alpha-Beta": 0.0,"Dispatch": 1.8628,"Clock": 0.10784,"Others": 0.00394},"3": {"PE": 64.2304,"Alpha-Beta": 0.0,"Dispatch": 1.6808,"Clock": 0.10784,"Others": 0.0017},"5": {"PE": 36.1344,"Alpha-Beta": 0.0,"Dispatch": 1.7372,"Clock": 0.10784,"Others": 0.0015},"6": {"PE": 36.4704,"Alpha-Beta": 0.0,"Dispatch": 1.786,"Clock": 0.10784,"Others": 0.00169},"7": {"PE": 62.4704,"Alpha-Beta": 0.0,"Dispatch": 1.8516,"Clock": 0.10784,"Others": 0.00574},"8": {"PE": 64.6944,"Alpha-Beta": 0.0,"Dispatch": 1.8592,"Clock": 0.10784,"Others": 0.00484},"9": {"PE": 66.3104,"Alpha-Beta": 0.0,"Dispatch": 1.8592,"Clock": 0.10784,"Others": 0.00202},"10": {"PE": 65.3184,"Alpha-Beta": 0.0,"Dispatch": 1.8628,"Clock": 0.10784,"Others": 0.00494},"11": {"PE": 63.9104,"Alpha-Beta": 0.0,"Dispatch": 1.8576,"Clock": 0.10784,"Others": 0.00424},"12": {"PE": 65.8304,"Alpha-Beta": 0.0,"Dispatch": 1.6388,"Clock": 0.10784,"Others": 0.00894}},"16": {"1": {"PE": 230.4896,"Alpha-Beta": 0.0,"Dispatch": 3.7288,"Clock": 0.21568,"Others": 0.00084},"2": {"PE": 262.6176,"Alpha-Beta": 0.0,"Dispatch": 3.7256,"Clock": 0.21568,"Others": 0.00394},"3": {"PE": 256.9216,"Alpha-Beta": 0.0,"Dispatch": 3.3616,"Clock": 0.21568,"Others": 0.0017},"5": {"PE": 144.5376,"Alpha-Beta": 0.0,"Dispatch": 3.4744,"Clock": 0.21568,"Others": 0.0015},"6": {"PE": 145.8816,"Alpha-Beta": 0.0,"Dispatch": 3.572,"Clock": 0.21568,"Others": 0.00169},"7": {"PE": 249.8816,"Alpha-Beta": 0.0,"Dispatch": 3.7032,"Clock": 0.21568,"Others": 0.00574},"8": {"PE": 258.7776,"Alpha-Beta": 0.0,"Dispatch": 3.7184,"Clock": 0.21568,"Others": 0.00484},"9": {"PE": 265.2416,"Alpha-Beta": 0.0,"Dispatch": 3.7184,"Clock": 0.21568,"Others": 0.00202},"10": {"PE": 261.2736,"Alpha-Beta": 0.0,"Dispatch": 3.7256,"Clock": 0.21568,"Others": 0.00494},"11": {"PE": 255.6416,"Alpha-Beta": 0.0,"Dispatch": 3.7152,"Clock": 0.21568,"Others": 0.00424},"12": {"PE": 263.3216,"Alpha-Beta": 0.0,"Dispatch": 3.2776,"Clock": 0.21568,"Others": 0.00894}}},"Square-BFP": {"8": {"1": {"PE": 55.7088,"Alpha-Beta": 4.552,"Dispatch": 2.0888,"Clock": 0.10784,"Others": 0.00104},"2": {"PE": 57.4688,"Alpha-Beta": 4.824,"Dispatch": 2.088,"Clock": 0.10784,"Others": 0.00324},"3": {"PE": 59.7408,"Alpha-Beta": 4.912,"Dispatch": 1.8792,"Clock": 0.10784,"Others": 0.00196},"5": {"PE": 31.9968,"Alpha-Beta": 2.104,"Dispatch": 1.64608,"Clock": 0.10784,"Others": 0.00572},"6": {"PE": 29.0528,"Alpha-Beta": 2.176,"Dispatch": 1.62744,"Clock": 0.10784,"Others": 0.00638},"7": {"PE": 57.9008,"Alpha-Beta": 4.948,"Dispatch": 2.0812,"Clock": 0.10784,"Others": 0.00694},"8": {"PE": 57.4368,"Alpha-Beta": 5.048,"Dispatch": 2.0736,"Clock": 0.10784,"Others": 0.00284},"9": {"PE": 58.6368,"Alpha-Beta": 5.048,"Dispatch": 2.0696,"Clock": 0.10784,"Others": 0.00221},"10": {"PE": 58.2688,"Alpha-Beta": 4.82,"Dispatch": 2.0748,"Clock": 0.10784,"Others": 0.00205},"11": {"PE": 55.9648,"Alpha-Beta": 4.828,"Dispatch": 2.0944,"Clock": 0.10784,"Others": 0.00464},"12": {"PE": 58.4448,"Alpha-Beta": 5.044,"Dispatch": 1.84684,"Clock": 0.10784,"Others": 0.00208}},"16": {"1": {"PE": 222.8352,"Alpha-Beta": 9.104,"Dispatch": 4.1776,"Clock": 0.21568,"Others": 0.00104},"2": {"PE": 229.8752,"Alpha-Beta": 9.648,"Dispatch": 4.176,"Clock": 0.21568,"Others": 0.00324},"3": {"PE": 238.9632,"Alpha-Beta": 9.824,"Dispatch": 3.7584,"Clock": 0.21568,"Others": 0.00196},"5": {"PE": 127.9872,"Alpha-Beta": 4.208,"Dispatch": 3.29216,"Clock": 0.21568,"Others": 0.00572},"6": {"PE": 116.2112,"Alpha-Beta": 4.352,"Dispatch": 3.25488,"Clock": 0.21568,"Others": 0.00638},"7": {"PE": 231.6032,"Alpha-Beta": 9.896,"Dispatch": 4.1624,"Clock": 0.21568,"Others": 0.00694},"8": {"PE": 229.7472,"Alpha-Beta": 10.096,"Dispatch": 4.1472,"Clock": 0.21568,"Others": 0.00284},"9": {"PE": 234.5472,"Alpha-Beta": 10.096,"Dispatch": 4.1392,"Clock": 0.21568,"Others": 0.00221},"10": {"PE": 233.0752,"Alpha-Beta": 9.64,"Dispatch": 4.1496,"Clock": 0.21568,"Others": 0.00205},"11": {"PE": 223.8592,"Alpha-Beta": 9.656,"Dispatch": 4.1888,"Clock": 0.21568,"Others": 0.00464},"12": {"PE": 233.7792,"Alpha-Beta": 10.088,"Dispatch": 3.69368,"Clock": 0.21568,"Others": 0.00208}}}}


def draw(n):
    fig, ax = plt.subplots(figsize=(15.0, 6.0))
    nb = len(VARIANTS)
    slot = 0.19
    offs = [(-1.5 + k) * slot for k in range(nb)]
    totals = {v: [] for v in VARIANTS}
    for i, m in enumerate(MODES):
        for v, off in zip(VARIANTS, offs):
            bottom = 0.0
            for sec in SECTIONS:
                val = DATA[v][str(n)][str(m)][sec]
                if val > 0:
                    ax.bar(i + off, val, slot * 0.92, bottom=bottom, color=COLORS[sec],
                           edgecolor="black", linewidth=0.35, zorder=3)
                bottom += val
            totals[v].append(bottom)

    mx = max(t for v in VARIANTS for t in totals[v])
    pad = 0.010 * mx
    CORRESP = {"Square": "Baseline", "Square-BFP": "Baseline-BFP"}
    for i, m in enumerate(MODES):
        for v, off in zip(VARIANTS, offs):
            if v not in CORRESP:
                continue
            t_ = totals[v][i]
            base_t = totals[CORRESP[v]][i]
            ax.text(i + off, t_ + pad, f"{t_ / base_t - 1.0:+.0%}", ha="center", va="bottom",
                    fontsize=6.0, rotation=90)

    ax.set_xticks(range(len(MODES)))
    ax.set_xticklabels([f"mode {m}" for m in MODES], fontsize=9)
    ax.set_xlim(-0.7, len(MODES) - 0.3)
    ax.set_ylabel("Dynamic power [mW]")
    ax.set_title(f"Per-Mode Dynamic Power — Baseline / Square / Baseline-BFP / Square-BFP, {n}x{n} Grid (ASAP7)")
    ax.set_ylim(0, mx * 1.16)
    ax.grid(axis="y", linestyle="--", alpha=0.35, zorder=0)

    legend = [Patch(facecolor=COLORS[s], edgecolor="black", linewidth=0.4, label=s) for s in SECTIONS]
    leg1 = ax.legend(handles=legend, loc="upper left", frameon=False, ncol=5, fontsize=9)
    ax.add_artist(leg1)
    ax.text(0.995, 0.97, "bars: " + " · ".join(VARIANTS), transform=ax.transAxes,
            ha="right", va="top", fontsize=8, color="#444")

    fig.tight_layout()
    out = Path(__file__).with_name(f"hist_syn_mode_pwr_{n}x{n}.png")
    fig.savefig(out, dpi=200, bbox_inches="tight")
    print(f"saved {out}")
    for m in MODES:
        i = MODES.index(m)
        vals = "  ".join(f"{v[:4]}={totals[v][i]:8.3f}" for v in VARIANTS)
        print(f"  mode {m:2}  {vals}")


for n in (8, 16):
    draw(n)
