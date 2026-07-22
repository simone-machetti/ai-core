# Optimization ideas — square vs baseline power

Candidate improvements to widen the power advantage of the square design ([top_NxN_sqr](../wiki/architectures/top_NxN_sqr.md)) over the baseline ([top_NxN](../wiki/architectures/top_NxN.md)) across all operating modes, in a fair and realistic way. Everything here is a **proposal** — nothing is implemented. The measured starting point, with tap operand isolation in the netlist, is [Synthesis Power](../wiki/experiments/syn_pwr.md) (−3.50 % at 8×8, −11.20 % at 16×16, all-mode average) and [Per-Mode Synthesis Power](../wiki/experiments/syn_mode_pwr.md) (per-mode margin at 8×8 from −16.94 % in mode 6 to +8.01 % in mode 1; the square loses modes 1 and 3 at 8×8 and mode 1 at 16×16).

## Root cause of the mode 1 loss

Mode 1 (8×4, all operands signed) loses not because the squarer is bad but because **Booth's power is magnitude-sensitive and the squarer's is not**:

- Booth radix-4 recoding turns small signed values into mostly-zero digit sets, and turns the long sign-extension 1-runs of small negative two's-complement values into single boundary digits. Measured on `dp_8`: unsigned B costs +34.6 % over signed B with identical bit patterns; mode 1's all-signed operands (mean |b| = 4 versus 7.5 for unsigned nibbles) make it Booth's cheapest operating point.
- The squarer's partial-product array is magnitude-blind: a small negative operand arrives as a long run of 1s and lights up partial products everywhere. `dp_8_sqr` has no signedness port and its power is nearly flat across modes.

The result in mode 1: per-tile saving collapses to 0.0433 mW against a full-cost α/β overhead of 0.7441 mW per row+column, pushing the crossover out to N ≈ 17.2.

Every idea below attacks one of two terms: **(A)** make the squarer reward small values the way Booth does, or **(B)** shrink the α/β tax so the tile difference stops deciding the outcome. The stimulus ideas define the platform on which A and B must be judged.

## Stimulus ideas

The current stimulus — uniform random operands, both A and B redrawn every cycle — is a legitimate hostile/worst-case anchor, but it is not what an AI workload looks like, and the two realism fixes push the comparison in **opposite directions**.

### 1. Value distribution: uniform → realistic

Uniform random maximizes mean operand magnitude and cycle-to-cycle bit flips. Real INT-quantized AI tensors are bell-shaped: weights roughly Gaussian/Laplacian, zero-mean, signed, concentrated at small magnitude (σ around FS/3–FS/4); activations concentrated near zero, often zero-inflated (post-ReLU sparsity 30–70 % in CNNs), unsigned in ReLU networks and signed in transformers.

Honest expectation: concentrating operands near zero moves *every* mode toward mode-1-like conditions — Booth's sweet spot — so the realistic distribution probably **shrinks** the square's tile-side margin. It is still the right thing to measure: uniform is already close to the most flattering distribution for the square, so publishing only uniform is not defensible.

Proposal: a `+dist=uniform|normal` plusarg with a σ parameter (clipped to range, drawn per the mode's signedness config), plus an optional zero-probability for A. Identical seeds and streams on both designs.

### 2. Operand cadence: stationary B (weights)

B carries the weights, and no real accelerator streams fresh weights every cycle — in a GEMM tiling each B element is reused across the whole M dimension; reuse factors run from dozens to thousands. Redrawing B every cycle is the worst possible case for any logic that depends on B alone, and the β generators are exactly that logic.

Holding B for T cycles:

- **Square** — the β array recomputes the same b² every cycle, so its combinational switching collapses to ~zero (only register clock power remains; see idea 6). Roughly the β half of the α/β overhead disappears. For mode 1, halving the 0.7441 mW overhead moves the crossover from N ≈ 17.2 to N ≈ 8.6 — a clear win at 16×16 and near-parity at 8×8.
- **Baseline** — the Booth recode and partial-product select lines go static, but the PP rows still toggle fully with streaming A. The saving is real but much smaller.

This change is both more realistic *and* favors the square, precisely in the α/β-dominated modes (1 and 3) where it currently loses. Streaming a fresh A every cycle is realistic and stays. The weight-load transient every T cycles must remain inside the measurement window so the reuse benefit is amortized, not assumed infinite; even T = 8–16 captures most of it, T = 64 is a conservative real-world figure.

Proposal: a `+breuse=T` plusarg — draw B once per T vectors, fresh A every vector; T = 1 reproduces today's numbers.

### Experiment matrix and fairness guardrails

Run {uniform, normal} × {T = 1, T = 64} and report the square-vs-baseline margin per mode per corner. Keep uniform / T = 1 as the published worst-case anchor. Take σ, sparsity and T from real workloads (or standard values, with a sensitivity sweep) — never tuned to flatter the square. Same seeds on both designs, as today.

Prediction for the realistic corner (normal, T = 64): the tile saving shrinks somewhat, the β overhead nearly vanishes, and the net per-mode picture improves — mode 1 moving from +8 % toward break-even at 8×8 and a clear win at 16×16. The two effects fight, so this is worth exactly one measurement.

## Microarchitecture ideas

### A — give the squarer Booth-like data sensitivity

**3. Absolute-value preconditioning: square |x| instead of x.** Since x² = |x|², a conditional negate in front of each squarer (tile, α and β generators alike) is mathematically free. Small negatives stop being long 1-runs and become short positives with leading zeros, so PP-array activity becomes proportional to magnitude — the same discount Booth gets. Cost: one XOR stage plus a +1 correction that folds into the PP array as a conditional LSB term. Cheapest structural answer to the sensitivity gap; helps every signed mode, not just mode 1. **Invisible under uniform stimulus** — must be evaluated on the realistic platform (ideas 1–2).

**4. Signed-digit (NAF/Booth-folded) squarer.** Recode the squarer input into canonical signed digits; cross-term activity then scales with (nonzero digits)² — quadratically quiet for small values, potentially better sensitivity than Booth itself. A real redesign of `dp_8_sqr` (signed partial products, ± handling). Held in reserve: idea 3 likely captures most of the benefit for a fraction of the effort.

### B — shrink the α/β overhead

**5. Narrow-mode masking inside the α/β generators.** Mode 1's b is 4-bit; if the β datapath is shared and sized for the widest packing, part of it computes sign extension for nothing in narrow modes. Same inline AND-mask idiom as the tap operand isolation ([pe_array § Operand isolation](../wiki/modules/pe_array.md#operand-isolation-en_level)), keyed on mode instead of tap level. Conditional on what the RTL actually shares — inspect before believing in it — but surgical: it cuts overhead precisely in the mode where overhead decides the result.

**6. Operand-reuse gating of α/β.** When an operand does not change, the α/β combinational switching already drops on its own (this is what idea 2 exposes); clock gating the α/β registers removes the residual clock power. Couples directly with the stationary-B cadence and with the existing per-row/per-column ICGs.

**7. Trim the square-side tap operand isolation.** The tree isolation is a baseline win (−0.95 % at 8×8) but a square regression (+2.32 %), and `en_level[2]` pays for nothing on either side. Making the isolation baseline-only, or trimming it to the levels that pay per variant, is a small but free, all-modes improvement.

### Rejected

- **Mode-1 bypass datapath** (a Booth path inside the square tile): doubles tile area to fix one mode — against the premise of the square design.
- **Zero-skip tiles**: when a = 0 the tile's square degenerates to a known value ((0+b)² = β), so a detect-and-freeze is possible — but it only pays under activation sparsity, so it belongs, if anywhere, after the stimulus work.
- **Workload weighting** of the per-mode mean: documentation, not a fix.

## Suggested order

1. Implement the stimulus knobs (ideas 1–2) and re-baseline all modes on the {distribution} × {reuse} matrix.
2. Evaluate idea 3 (abs preconditioning) together with the cheap cleanups 7 and 5 on that platform.
3. Escalate to idea 4 (signed-digit squarer) only if the mode 1 gap persists.

Rationale for the order: the A-family fixes are invisible under uniform stimulus — implementing them first and measuring under uniform would wrongly conclude they are worthless.
