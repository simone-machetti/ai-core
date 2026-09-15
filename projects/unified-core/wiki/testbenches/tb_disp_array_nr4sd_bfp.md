# Dispatch Array (NR4SD BFP) Testbench

## Purpose

`tb_disp_array_nr4sd_bfp` verifies the NR4SD dispatch **pair** — [disp_array_b_nr4sd_bfp](../modules/disp_array_b_nr4sd_bfp.md) and the plain [disp_array_a](../modules/disp_array_a.md) — against a golden model, for all 11 operating modes. Both are driven with the mode's *real* dispatch control vector: block selects, B-gate ops and per-DP8 B signedness taken verbatim from `ctrl`'s lookup tables.

## Parameters

| Parameter  | Default | Description                              |
| ---------- | ------- | ---------------------------------------- |
| `NUM_RAND` | `500`   | Random 256-bit operand vectors per mode. |

## Run

```
make sim PROJECT=unified-core TOP_LEVEL=disp_array_b_nr4sd_bfp TB=tb_disp_array_nr4sd_bfp
```

## What it checks

| Output                            | Golden                                                                                                                                   |
| --------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `a_dp8_o`                         | block select → duplication onto both DP8s of a pair.                                                                                     |
| `b_nr4sd_dp8_o` / `b_booth_dp8_o` | block select → high/low split → per-int4 gate with the cross-half carry → cross-nibble link → hybrid recode, compared **by digit value**. |

Any mismatch is **fatal**.

## How it checks

### The B side is where the work is

This is the counterpart of [tb_disp_array_bpl_b_bfp](./tb_disp_array_bpl_b_bfp.md) with the roles exchanged: there the golden reproduced A's resolution, here it reproduces the whole B chain. Three steps, in the order the RTL takes them:

```systemverilog
// 1. route, split, gate - the same value the DP8 multiplies
gres            = gate_nib(nib, CTR_L[mi][p], 1'b0);
gated[2*p+1][e] = gres[B_ELEM_WIDTH-1:0];
lo_c[e]         = gres[B_ELEM_WIDTH];
...
gres            = gate_nib(nib, CTR_H[mi][p], lo_c[e]);
gated[2*p+0][e] = gres[B_ELEM_WIDTH-1:0];
```

```systemverilog
// 2. cross-nibble link: DP8 i takes the MSB of the gated nibble of DP8 i+1
//    when that DP8 holds a lower nibble; never across a quad boundary
if (i % 4 == 3) cin[i][e] = 1'b0;
else            cin[i][e] = !IS_SIGNED_B[mi][i+1] && gated[i+1][e][B_ELEM_WIDTH-1];
```

```systemverilog
// 3. recode and compare by digit value
recode(gated[i][e], cin[i][e], d0_exp, d1_exp);
```

The order matters: the recode must be of the **gated** value, and the link must be taken after the gate too. A golden that recoded before gating would pass on the pass modes and fail on the negate and idle ones — which is exactly what the negate-mode vectors are there to catch.

### Comparison by digit value

The software recoder is written from the arithmetic definition of the hybrid — `s = raw + carry`, emit `s − 4` and a carry when `s ≥ 3`; Booth on the top pair as the pair read signed plus that carry — and the DUT's 2-bit code and 3-bit window are decoded with their cells' tables before comparing:

```systemverilog
d0_got = dec_nr4sd(b_nr4sd_dp8[i][e*CODE_WIDTH +: CODE_WIDTH]);
d1_got = dec_booth(b_booth_dp8[i][e*BSEL_WIDTH +: BSEL_WIDTH]);
if (d0_got !== d0_exp || d1_got !== d1_exp) begin
```

So the bench accepts any window that means the right Booth digit rather than the wiring [nr4sd_r4](../modules/nr4sd_r4.md) happens to emit.

### The modes exercise the carry and the link

The negate modes are driven with `ctrl`'s carry-chained control (`GATE_NEG` on the low half, `GATE_NEG_CARRY` on the high half), so the cross-half carry is exercised — and, because the recoders sit downstream of it, so is the recode of a negated operand. The int16 modes (8, 9, 12) drive the quad pattern `is_signed_b = 1, 0, 0, 0`, exercising the cross-pair link `4q+1 ← 4q+2`; the int8 modes link within each pair (`2p ← 2p+1`); an all-int4 mode such as mode 1 links nothing. Each mode runs `NUM_RAND` random vectors plus a directed ramp (`a` bytes and `b` nibbles counting up), pushed through the input registers one clock at a time.

Result: **11/11 modes PASSED**, 0 mismatches.

Source: [tb_disp_array_nr4sd_bfp.sv](../../tb/tb_disp_array_nr4sd_bfp.sv) — DUTs: [disp_array_b_nr4sd_bfp](../modules/disp_array_b_nr4sd_bfp.md), [disp_array_a](../modules/disp_array_a.md)
