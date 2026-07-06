# PE Array Testbench

## Purpose

`tb_pe_array` verifies [pe_array](../architecture/pe_array.md) wired downstream of [disp_array](../architecture/disp_array.md). Every one of the 11 modes is checked as a plain matrix multiply `X = A · B`, using a golden model that knows nothing about the DUT's adder tree, crossover, per-level shifts, or `sel_shift` — so a bug in any of those surfaces as a mismatch a tree-shaped golden would hide.

## Parameters

| Parameter  | Default | Description                                                           |
| ---------- | ------- | --------------------------------------------------------------------- |
| `NUM_RAND` | `2000`  | Number of random `A`,`B` matrix pairs generated and checked per mode. |

The two DUTs are instantiated with their defaults; the tb pins the shape with localparams `NUM_BLK=4`, `BLK_WIDTH=64`, `NUM_PAIR=8`, `NUM_DP8=16`, the per-level tap widths (`L0=18`, `L1=29`, `L2=37`, `L3=38` bits), and the matmul bounds `MAXM=2`, `MAXK=32`, `MAXN=4`, `MAXO=8`, and does not override any DUT parameter.

## Run

```
make sim PROJECT=ai-core TOP_LEVEL=pe_array PARAMS="NUM_RAND=2000"
```

## What it checks

| Aspect          | Detail                                                                                                                                                |
| --------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| Modes           | all 11 (8 real + 3 complex: 10, 11, 12)                                                                                                               |
| Golden          | independent `X = A·B`; complex as 4 real products — `Re = Σ a_r·b_r − a_i·b_i`, `Im = Σ a_r·b_i + a_i·b_r`                                            |
| Packing         | `A`/`B` placed at byte/nibble positions from the sheet's **Storage** table, never from `SEL` — so a wrong `SEL` route is caught                       |
| Compare         | each golden `X` element checked at the carry-save tap (level + node) that is supposed to carry it                                                     |
| Why independent | a tree-shaped golden shares the DUT's crossover/weights and hides those bugs; this flat `A·B` does not (a broken L0 crossover mismatches immediately) |

## How it checks

### Per-mode shapes and control

Each mode has an entry in `MM_DIMS = {M, K, N, PA, PB, cplx, NOUT}` giving the matrix shape, the `A`/`B` element precisions (`PA`/`PB` bits), whether it is complex, and how many outputs it produces. `set_controls` drives the DUT's routing for the mode — `SEL_A`/`SEL_B`, the B-gate ops `CTR_L`/`CTR_H`, the per-DP8 signedness flags `IS_SIGNED_A`/`IS_SIGNED_B`, and the tree shift `SEL_SHIFT` — all read from `modes.xlsx`. Crucially these drive *only* the DUT; the golden and the packing below ignore them.

### Stimulus generation

`rand_matrices` fills `A` and `B` with fresh signed values sized to the mode's precision. `rand_signed` draws a signed value of `PA`/`PB` bits, biased toward the precision's extremes (most-negative / max-positive roughly 40% of the time) so the tree's sign-consistency corners are reached in thousands of vectors rather than millions. The imaginary part of `B`, however, is drawn from a **symmetric** range by `rand_signed_sym`:

```systemverilog
function automatic logic signed [15:0] rand_signed_sym(input int width);
    int m;
    m = (1 << (width - 1)) - 1;
    return 16'($signed(($urandom % (2*m + 1)) - m));
endfunction
```

This excludes the most-negative value (`−128` for int8, `−32768` for int16). The complex math needs `−b_i`, and negating the most-negative value would overflow the width — whether that negation happens in hardware (the B-gate in modes 10/11) or in software (mode 12 below). Drawing `B_im` symmetrically keeps every negation exact.

### The golden reference

`golden` computes each output `X` directly as `A · B` in wide `longint` accumulators, treating every mode — real or complex — as the same nested sum. Complex is just four real products; for a purely real mode `A_im`/`B_im` are zero and the imaginary terms drop out:

```systemverilog
for (int k = 0; k < K; k++) begin
    re = re + longint'(A_re[m][k]) * longint'(B_re[k][n])
            - longint'(A_im[m][k]) * longint'(B_im[k][n]);
    im = im + longint'(A_re[m][k]) * longint'(B_im[k][n])
            + longint'(A_im[m][k]) * longint'(B_re[k][n]);
end
```

This model is flat: it never forms the DUT's partial sums, never applies the crossover or per-level shifts, and never uses `SEL`. That independence is the whole point — a golden that re-derived `X` by mimicking the tree would share the DUT's crossover, weight, and shift assumptions and cancel out exactly the bugs those introduce. Because this one recomputes `A·B` from scratch, a broken tree, a wrong weight, a mis-wired crossover, or a bad route all show up as a numeric mismatch.

### Packing from the Storage table

`pack` writes the random `A`/`B` values into the two 256-bit operand words at the byte/nibble positions the sheet's **Storage** table assigns — held in `MM_RE_A`/`MM_IM_A` (byte positions for `A`) and `MM_RE_B`/`MM_IM_B` (nibble positions for `B`). A position of `255` is a sentinel meaning "not stored" and is skipped; for 16-bit precision the high byte position is the next byte field (`>> 8`):

```systemverilog
pos = MM_RE_A[mi][m][k] & 255;
if (pos != 255) pe_in_a[pos*8 +: 8] = A_re[m][k][7:0];
if (PA == 16) begin
    pos = (MM_RE_A[mi][m][k] >> 8) & 255;
    if (pos != 255) pe_in_a[pos*8 +: 8] = A_re[m][k][15:8];
end
```

These positions come from the Storage table, **not** from `SEL`. `SEL` only drives routing inside the DUT and is never used to place data — so if a mode's `SEL` vector is wrong, the data still lands where storage says, the DUT routes it somewhere else, and the compare fails. That is how a wrong `SEL` is caught.

### Mode 12: the pre-negated complex-16 pack

Mode 12 (complex int16 × int16) does not gate `−b_i` in hardware; the negation is **pre-stored** in software. `pack_b_c16c16` lays out `B` so the real output reads `(R, −I)` and the imaginary output reads `(I, R)`, with `put_b16` interleaving each 16-bit value across a high/low block pair. The `−B_im` term is written already negated (relying on the symmetric draw above so it fits):

```systemverilog
task automatic pack_b_c16c16;
    for (int k = 0; k < 4; k++) begin
        put_b16( B_re[k][0], 0, 1, k);
        put_b16(-B_im[k][0], 0, 1, 4 + k);
        put_b16( B_im[k][0], 2, 3, k);
        put_b16( B_re[k][0], 2, 3, 4 + k);
    end
endtask
```

For the int8 complex modes 10 and 11 the tb packs `B_im` un-negated and lets the DUT's B-gate (`CTR = negate`) form `−b_i` in hardware instead.

### Drive/sample timing

The path is a **two-cycle pipeline**: `disp_array` registers its inputs and `pe_array` registers its tap outputs. So after packing, the loop advances two clock edges before sampling, then waits `#1` for the combinational taps to settle:

```systemverilog
rand_matrices(mi);
golden(mi);
pack(mi);
@(posedge clk_i);
@(posedge clk_i);
#1;
compare(mi);
```

### Reading the taps and comparing

`pe_array` exposes carry-save taps at every tree level (`l0..l3`, each a `sum`/`carry` pair). `resolve_tap` reconstructs the true integer at a given level/node by sign-extending both rows and adding — the same independent-sign-extension property `dp_8` guarantees:

```systemverilog
2: return longint'($signed(l2_sum[node])) + longint'($signed(l2_carry[node]));
```

`compare` walks the mode's outputs. `TAP_LEVEL[mi]` says which tree level carries this mode's results, and `MM_OUT[mi][o]` gives `{m, n, real_node, imag_node}` — the matrix indices plus which tap node holds the real and (if `≥ 0`) imaginary parts. Each is resolved and checked against the golden with `!==`:

```systemverilog
rn = MM_OUT[mi][o][2];
in = MM_OUT[mi][o][3];
r = resolve_tap(lvl, rn);
if (r !== X_re[o]) begin err = err + 1; $display("mode %0d output %0d Re: golden=%0d dut=%0d", ...); end
if (in >= 0) begin
    r = resolve_tap(lvl, in);
    if (r !== X_im[o]) begin err = err + 1; $display("mode %0d output %0d Im: golden=%0d dut=%0d", ...); end
end
```

### Reporting

Errors accumulate in `err`. Each mode snapshots `err` before its batch and prints `mode N: PASS` if it did not grow, or `FAIL (k mismatches)` otherwise. At the end the tb prints `M/11 modes passed (E total mismatches)` and `$finish`es — a clean run reports `11/11 ... 0 total mismatches`.

Source: [tb_pe_array.sv](../../tb/tb_pe_array.sv) — DUT: [pe_array](../architecture/pe_array.md)
