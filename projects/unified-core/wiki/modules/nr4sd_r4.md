# NR4SD Radix-4

`nr4sd_r4` — hybrid NR4SD⁺/Booth radix-4 recoder: turns one B nibble plus a carry-in into **two** radix-4 digits — a 2-bit NR4SD⁺ code at weight 1 and a 3-bit Booth window at weight 4 — with no correction digit. It is the recoder cell of [disp_array_b_nr4sd_bfp](./disp_array_b_nr4sd_bfp.md), one per nibble per DP8, and the sibling of [booth_r4](./booth_r4.md).

## Purpose

Recodes the 4-bit multiplier `b_i` so that [dp_8_nr4sd_bfp](./dp_8_nr4sd_bfp.md) needs **two** partial products per lane instead of [dp_8](./dp_8.md)'s three. `booth_r4` needs its third window only to give an *unsigned* `b` its positive top bit; here every nibble is read as **signed** and the missing `16·b₃` of a lower nibble is repaid by the nibble above through `c_in_i`, so the recoding of one nibble is always

```
d₀ + 4·d₁  =  signed(b_i) + c_in_i
```

Two NR4SD⁺ digits alone span `[−5, +10]` and miss `−6, −7, −8` — that is what forced the first NR4SD build into three digits. A Booth digit on top spans `4·[−2, +2] + [−1, +2] = [−9, +10]`, which covers a signed nibble plus carry, `[−8, +8]`, with no third digit. The Booth pair costs 3 bits instead of 2 and confines the `−2A` multiple to one cell per lane; the NR4SD⁺ pair keeps its 2-bit code and never needs `−2A`. Five control bits per nibble, against six for three NR4SD⁺ digits and nine for three Booth digits.

Unlike `booth_r4`, this module never sees the multiplicand: it emits digit **codes**, not partial products. The cells that turn a code into a multiple of A — [nr4sd_r4_cell](./nr4sd_r4_cell.md) and [booth_r4_cell](./booth_r4_cell.md) — stay in the DP8, which is what lets the recoder be hoisted into the column dispatcher and shared by every PE of the column.

## Parameters

| Parameter    | Default | Description                                       |
| ------------ | ------- | ------------------------------------------------- |
| `IN_WIDTH_B` | 4       | Bit width of the nibble `b_i` (even, at least 4). |

Derived: `NUM_PAIR = IN_WIDTH_B/2` (radix-4 digits), `CODE_WIDTH = 2` (one NR4SD⁺ code), `SEL_WIDTH = 3` (the Booth window), `NR4SD_WIDTH = (NUM_PAIR − 1)·CODE_WIDTH` (all NR4SD⁺ codes together). For the default nibble that is two digits: one NR4SD⁺ code (2 bits) and one Booth window (3 bits).

## Interface

| Signal      | Dir | Width         | Description                                                                    |
| ----------- | --- | ------------- | ------------------------------------------------------------------------------ |
| `b_i`       | in  | `IN_WIDTH_B`  | The nibble — always read as signed.                                            |
| `c_in_i`    | in  | 1             | Carry-in, the cross-nibble link: `b₃` of the slice below, otherwise `0`.       |
| `b_nr4sd_o` | out | `NR4SD_WIDTH` | NR4SD⁺ codes of the low pairs, code `j` at `[2j +: 2]`, weight `4ʲ`.           |
| `b_booth_o` | out | `SEL_WIDTH`   | Booth window `{b_hi, b_lo, carry}` of the top pair, weight `4^(NUM_PAIR−1)`.   |

There is **no signedness input**: the nibble is signed by construction, and whether a carry enters is decided by the dispatcher. Combinational.

## Instantiation

```systemverilog
nr4sd_r4 #(
    .IN_WIDTH_B(4)
) nr4sd_r4_i (
    .b_i      (nib),        // gated 4-bit nibble
    .c_in_i   (c_in),       // cross-nibble link
    .b_nr4sd_o(b_nr4sd),    // 2-bit NR4SD+ code, weight 1
    .b_booth_o(b_booth)     // 3-bit Booth window, weight 4
);
```

## Internal logic

Purely combinational — no clock, no storage. A carry chain runs up the pairs of `b_i`, seeded by `c_in_i`; every pair but the top one is recoded NR4SD⁺, the top pair is handed to Booth as a window.

### The low pair: NR4SD⁺ with the carry in

The pair `b₁b₀` plus the incoming carry forms `s₀ = 2·b₁ + b₀ + c ∈ [0, 4]`; a sum of 3 or more is pushed up as a carry, which leaves a digit in the non-redundant set `{−1, 0, +1, +2}`: `c₁ = [s₀ ≥ 3]`, `d₀ = s₀ − 4·c₁`. In the RTL that is a few gates per pair:

```systemverilog
assign carry[0] = c_in_i;
...
for (j = 0; j < NUM_PAIR - 1; j++) begin : gen_nr4sd
    logic b_hi;
    logic b_lo;
    assign b_hi = b_i[2*j+1];
    assign b_lo = b_i[2*j];
    assign b_nr4sd_o[j*CODE_WIDTH]   = b_lo ^ carry[j];
    assign b_nr4sd_o[j*CODE_WIDTH+1] = b_hi ^ (b_lo & carry[j]);
    assign carry[j+1]                = b_hi & (b_lo | carry[j]);
end
```

The code map is the one [nr4sd_r4_cell](./nr4sd_r4_cell.md) decodes — `00 → 0`, `01 → +1`, `10 → +2`, `11 → −1`:

| `b₁` | `b₀` | `c` | `s₀` | `d₀` | `c₁` | `code` |
| ---- | ---- | --- | ---- | ---- | ---- | ------ |
| 0    | 0    | 0   | 0    | `0`  | 0    | `00`   |
| 0    | 0    | 1   | 1    | `+1` | 0    | `01`   |
| 0    | 1    | 0   | 1    | `+1` | 0    | `01`   |
| 0    | 1    | 1   | 2    | `+2` | 0    | `10`   |
| 1    | 0    | 0   | 2    | `+2` | 0    | `10`   |
| 1    | 0    | 1   | 3    | `−1` | 1    | `11`   |
| 1    | 1    | 0   | 3    | `−1` | 1    | `11`   |
| 1    | 1    | 1   | 4    | `0`  | 1    | `00`   |

### The top pair: a Booth window, no logic

The top pair is **not** decoded. Read as a signed 2-bit value plus the carry from below, `−2·b₃ + b₂ + c₁`, it is exactly Booth's window `{b[2i+1], b[2i], b[2i−1]}` with `c₁` standing in for the bit below — so the module emits the window as wiring and lets the existing [booth_r4_cell](./booth_r4_cell.md) decode it:

```systemverilog
assign b_booth_o = {b_i[IN_WIDTH_B-1], b_i[IN_WIDTH_B-2], carry[NUM_PAIR-1]};
```

| `b₃` | `b₂` | `c₁` | `d₁ = −2·b₃ + b₂ + c₁` | `booth_r4_cell` |
| ---- | ---- | ---- | ---------------------- | --------------- |
| 0    | 0    | 0    | `0`                    | 0               |
| 0    | 0    | 1    | `+1`                   | `+1×`           |
| 0    | 1    | 0    | `+1`                   | `+1×`           |
| 0    | 1    | 1    | `+2`                   | `+2×`           |
| 1    | 0    | 0    | `−2`                   | `−2×`           |
| 1    | 0    | 1    | `−1`                   | `−1×`           |
| 1    | 1    | 0    | `−1`                   | `−1×`           |
| 1    | 1    | 1    | `0`                    | 0               |

No carry leaves the top pair: there is no third digit. Substituting `s₀ = d₀ + 4·c₁` into the nibble's signed value gives `V = 4·(−2·b₃ + b₂) + s₀ = 4·d₁ + d₀`, the reconstruction identity above — see [nr4sd_2pp.tex](../../doc/formulas/encodings/nr4sd_2pp.tex).

### The carry-in is the cross-nibble link

`c_in_i` is what makes a two-digit nibble exact inside a wider element. A nibble that is a **lower** slice of an int8/int16 is read as signed too, which is `16·b₃` too small; the nibble above repays it by taking `c_in_i = b₃` of the slice below, gaining `+1` — `+16` on the element — exactly when `b₃ = 1`. The top nibble of an element, a whole int4 and an idle lane take `c_in_i = 0`. The dispatcher owns that wiring, after its gates: see [disp_array_b_nr4sd_bfp](./disp_array_b_nr4sd_bfp.md). The `×16` between the two DP8s in the tree of [pe_array_nr4sd_bfp](./pe_array_nr4sd_bfp.md) cancels the two errors element by element, whatever the grouping — [booth_2pp.tex](../../doc/formulas/encodings/booth_2pp.tex), Steps 4–5.

### Zero code

Both zero codes are all-zero — NR4SD⁺ `00` and Booth window `000` — so `b_i = 0` with `c_in_i = 0` recodes to the all-zero bus, and an all-zero encoded bus is the zero multiplier. That is what lets [pe_nr4sd_bfp](./pe_nr4sd_bfp.md) AND-mask the recoded buses to quiet a gated lane, as [pe_bfp](./pe_bfp.md) masks the raw operands.

### Weighting

The digits are emitted **unweighted**. Code `j` has radix-4 place value `4ʲ`; the consumer ([dp_8_nr4sd_bfp](./dp_8_nr4sd_bfp.md)) shifts the Booth partial product left by 2 before summing:

```
a × (signed(b) + c_in) = pp_nr4sd + (pp_booth << 2)
```

## Verification

[tb_nr4sd_r4](../testbenches/tb_nr4sd_r4.md) is **exhaustive** — all 16 nibble values under both carry-ins, **32/32**. It reconstructs `d₀ + 4·d₁` from the codes and checks it against `signed(b) + c_in`, checks the digit ranges, the all-zero code, and that the 16 encodings are pairwise distinct under each carry-in; the Booth window is decoded by Booth's own rule, `−2·w₂ + w₁ + w₀`, so any window that means the right digit is accepted.

Source: [nr4sd_r4.sv](../../rtl/nr4sd_r4.sv) — Testbench: [tb_nr4sd_r4.sv](../../tb/tb_nr4sd_r4.sv) — Diagram: [nr4sd_2pp](../../doc/diagrams/nr4sd_2pp.excalidraw) — Derivation: [nr4sd_2pp.tex](../../doc/formulas/encodings/nr4sd_2pp.tex)
