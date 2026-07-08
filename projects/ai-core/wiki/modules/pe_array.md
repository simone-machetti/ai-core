# PE Array

`pe_array` — instantiates the 16 [dp_8](./dp_8.md) cores and reduces their carry-save outputs through a 4-level tree with programmable per-level shifts, exposing a carry-save tap at every level so a mode reads its results at the depth matching its output count.

## Purpose

Each DP8 produces one length-8 dot product in 20-bit carry-save form; the tree sums those 16 partial results with the per-mode radix weights and leaves the result in carry-save for the accumulator to resolve. A mode's outputs appear at the tree level whose node count matches the number of parallel results: 8 results at L0, 4 at L1, 2 at L2, 1 at L3. The 16 DP8s live here, so their per-lane signedness (`is_signed_a`/`is_signed_b`) arrives from `pe_ctrl` and is wired straight to them; the routed operands arrive from the [disp_array](./disp_array.md).

## Parameters

None — fixed to the PE configuration. `pe_array` exposes no external parameters; the shape is baked in as `localparam`s. The key ones:

| Localparam                    | Value             | Meaning                                                        |
| ----------------------------- | ----------------- | -------------------------------------------------------------- |
| `NUM_DP8`                     | 16                | DP8 cores driving the tree.                                    |
| `NUM_L0`/`NUM_L1`/`NUM_L2`    | 8 / 4 / 2         | node count at L0/L1/L2 (L3 is a single node).                  |
| `DP8_WIDTH`                   | 20                | each DP8 carry-save row width (sign-consistent).               |
| `SH0`/`SH1`/`SH2`             | 8 / 4 / 8         | per-level left-shift amount (L0/L1/L2; L3 has no shift).       |
| `L0_WIDTH`…`L3_WIDTH`         | 28 / 32 / 40 / 40 | internal node width at each level (what feeds the next level). |
| `L0_TAP_WIDTH`…`L3_TAP_WIDTH` | 18 / 29 / 37 / 38 | tap width exported to the accumulator at each level.           |

Every `cpr_w_n` in the tree runs with `EXT = 0` — the DP8's 4 guard bits are headroom enough for all four levels (see [Width growth and the taps](#width-growth-and-the-taps)). Everything runs signed: `IS_SIGNED = 1'b1` on every `shift_n`, `ext_n`, and `cpr_w_n`.

## Interface

| Signal                       | Dir | Width   | Description                                                             |
| ---------------------------- | --- | ------- | ----------------------------------------------------------------------- |
| `clk_i`                      | in  | 1       | Clock.                                                                  |
| `rst_ni`                     | in  | 1       | Asynchronous active-low reset.                                          |
| `a_dp8_i[0:15]`              | in  | 64 each | A operand per DP8 (8 × int8), from `disp_array`.                        |
| `b_dp8_i[0:15]`              | in  | 32 each | B operand per DP8 (8 × int4), from `disp_array`.                        |
| `is_signed_a_i[0:15]`        | in  | 1 each  | Per-DP8 multiplicand signedness, from `pe_ctrl`.                        |
| `is_signed_b_i[0:15]`        | in  | 1 each  | Per-DP8 multiplier signedness, from `pe_ctrl`.                          |
| `sel_shift_i[2:0]`           | in  | 1 each  | Per-level shift enable: `[0]`=L0 `<<8`, `[1]`=L1 `<<4`, `[2]`=L2 `<<8`. |
| `l0_sum_o`/`l0_carry_o[0:7]` | out | 18 each | L0 taps (carry-save).                                                   |
| `l1_sum_o`/`l1_carry_o[0:3]` | out | 29 each | L1 taps.                                                                |
| `l2_sum_o`/`l2_carry_o[0:1]` | out | 37 each | L2 taps.                                                                |
| `l3_sum_o`/`l3_carry_o`      | out | 38      | L3 tap.                                                                 |

Every tap is a carry-save pair (`sum + carry`); the tree never resolves — the accumulator does, splitting each tap into its lanes.

## Instantiation

```systemverilog
pe_array pe_array_i (
    .clk_i(clk_i), .rst_ni(rst_ni),
    .a_dp8_i(a_dp8), .b_dp8_i(b_dp8),
    .is_signed_a_i(is_signed_a), .is_signed_b_i(is_signed_b),
    .sel_shift_i(sel_shift),
    .l0_sum_o(l0_sum), .l0_carry_o(l0_carry),
    .l1_sum_o(l1_sum), .l1_carry_o(l1_carry),
    .l2_sum_o(l2_sum), .l2_carry_o(l2_carry),
    .l3_sum_o(l3_sum), .l3_carry_o(l3_carry)
);
```

## Internal logic

The datapath is: **16 DP8 cores → a 4-level carry-save reduction tree of 15 compressors (8 + 4 + 2 + 1) → carry-save taps at each level.** Nothing is ever carry-propagated inside `pe_array`; every wire is a signed carry-save `(sum, carry)` pair and the accumulator resolves the taps it reads. The instance counts are:

- 16 `dp_8` (one per input operand pair),
- 15 `cpr_w_n` 4:2 compressors (8 at L0, 4 at L1, 2 at L2, 1 at L3),
- 14 `shift_n` and 14 `ext_n` (at L0/L1/L2 — L3 merges two equal-width operands directly, with no weighting),
- 2 `reg_n` banks (L0 sum and L0 carry — the only registered stage).

### The 16 DP8 cores

Each 64-bit `a_dp8_i[i]` packs eight `int8` lanes and each 32-bit `b_dp8_i[i]` packs eight `int4` lanes. The `gen_dp8` block unpacks them and feeds one [dp_8](./dp_8.md), which returns a 20-bit carry-save dot product:

```systemverilog
for (i = 0; i < NUM_DP8; i++) begin : gen_dp8
    logic [IN_WIDTH_A-1:0] a_lane [0:LANES-1];
    logic [IN_WIDTH_B-1:0] b_lane [0:LANES-1];
    for (ln = 0; ln < LANES; ln++) begin : gen_lane
        assign a_lane[ln] = a_dp8_i[i][ln*IN_WIDTH_A +: IN_WIDTH_A];
        assign b_lane[ln] = b_dp8_i[i][ln*IN_WIDTH_B +: IN_WIDTH_B];
    end
    dp_8 dp_8_i (
        .a_i(a_lane), .b_i(b_lane),
        .is_signed_a_i(is_signed_a_i[i]), .is_signed_b_i(is_signed_b_i[i]),
        .sum_o(dp8_sum[i]), .carry_o(dp8_carry[i])
    );
end
```

`is_signed_a_i[i]`/`is_signed_b_i[i]` are per-DP8, because in the wider modes an operand field's high half is signed and its low half unsigned — so different DP8s run different sign combinations. The 16 results land in `dp8_sum[0:15]` / `dp8_carry[0:15]`, the leaves of the tree.

### Tree overview (4 levels, 15 compressors)

The tree is a balanced binary reduction. Each node merges **two** carry-save operands (four rows: two sum/carry rows each) back down to one carry-save pair with a `cpr_w_n` 4:2. Halving the node count each level gives 8 → 4 → 2 → 1:

| Level | Nodes | Shift                    | Combines                           | Registered |
| ----- | ----- | ------------------------ | ---------------------------------- | ---------- |
| L0    | 8     | `<<8` (`sel_shift_i[0]`) | a **crossed** DP8 pair (see below) | yes        |
| L1    | 4     | `<<4` (`sel_shift_i[1]`) | `l1[j] = l0[2j] + l0[2j+1]`        | no         |
| L2    | 2     | `<<8` (`sel_shift_i[2]`) | `l2[k] = l1[2k] + l1[2k+1]`        | no         |
| L3    | 1     | none                     | `l3 = l2[0] + l2[1]`               | no         |

In every node the **even child** (`l0[2j]`, `l1[2k]`, `l2[0]`) is the higher-weight operand and is the one that gets shifted; the odd child is only sign-extended to match. L1/L2/L3 pair up strictly adjacent nodes — only L0 crosses.

### Anatomy of a tree node (shift_n + ext_n + cpr_w_n)

Every node has the same three-primitive shape. Take L0 as the model. The higher-weight operand's `(sum, carry)` pair (`SIZE = 2`) goes through a [shift_n](./shift_n.md); the lower-weight operand's pair goes through an [ext_n](./ext_n.md) that widens it by the same amount so both align; the four resulting rows feed a [cpr_w_n](./cpr_w_n.md) 4:2:

```systemverilog
shift_n #(.WIDTH(DP8_WIDTH), .SIZE(2), .SHIFT(SH0), .IS_SIGNED(1'b1)) shift_n_i (
    .in_i(hi_in), .sel_i(sel_shift_i[0]), .out_o(hi_sh)
);
ext_n #(.WIDTH(DP8_WIDTH), .SIZE(2), .EXT(SH0), .IS_SIGNED(1'b1)) ext_n_i (
    .in_i(lo_in), .out_o(lo_ext)
);

assign cpr_in[0] = hi_sh[0];   // shifted sum
assign cpr_in[1] = hi_sh[1];   // shifted carry
assign cpr_in[2] = lo_ext[0];  // extended sum
assign cpr_in[3] = lo_ext[1];  // extended carry

cpr_w_n #(.IN_WIDTH(L0_WIDTH), .IN_SIZE(4), .EXT(0), .IS_SIGNED(1'b1)) cpr_w_n_i (
    .in_i(cpr_in), .sum_o(l0_sum[n]), .carry_o(l0_carry[n])
);
```

- `shift_n` with `SHIFT = SH0 = 8`: when `sel_shift_i[0] = 1` it multiplies the higher-weight operand by `2^8`; when `0` it sign-extends it to the same `WIDTH + SHIFT` output width. Either way the output is `DP8_WIDTH + SH0 = 28` bits, so the compressor sees a fixed width regardless of the enable.
- `ext_n` with `EXT = SH0 = 8`: sign-extends the lower-weight operand from 20 to 28 bits so it lines up with the shifted operand.
- `cpr_w_n` with `IN_SIZE = 4`, `IN_WIDTH = L0_WIDTH = 28`, `EXT = 0`: reduces the four 28-bit rows to a 28-bit carry-save pair.

`IN_SIZE = 4` is exactly "two operands × (sum + carry)". L1 and L2 are the same shape scaled up (`WIDTH` and `SHIFT` grow; every compressor keeps `EXT = 0`); L3 is the one exception — see [Width growth](#width-growth-and-the-taps).

### The L0 crossover

L0 is the only level that does **not** pair adjacent DP8s. The `gen_l0` block computes each node's two DP8 indices from the node number `n`:

```systemverilog
localparam int CX0 = 4*(n/2) + (n%2);
localparam int CX1 = CX0 + 2;
...
assign hi_in[0] = dp8_sum[CX0];   // higher weight → shifted
assign hi_in[1] = dp8_carry[CX0];
assign lo_in[0] = dp8_sum[CX1];   // lower weight → extended
assign lo_in[1] = dp8_carry[CX1];
```

`CX0`/`CX1` step by 2, so a node mixes DP8s from two different `disp_array` 2×DP8 pairs (equivalently `l0[2g] = dp8[4g] + dp8[4g+2]`, `l0[2g+1] = dp8[4g+1] + dp8[4g+3]`):

| L0 node | DP8s combined |     | L0 node | DP8s combined   |
| ------- | ------------- | --- | ------- | --------------- |
| `l0[0]` | dp8 0 + dp8 2 |     | `l0[4]` | dp8 8 + dp8 10  |
| `l0[1]` | dp8 1 + dp8 3 |     | `l0[5]` | dp8 9 + dp8 11  |
| `l0[2]` | dp8 4 + dp8 6 |     | `l0[6]` | dp8 12 + dp8 14 |
| `l0[3]` | dp8 5 + dp8 7 |     | `l0[7]` | dp8 13 + dp8 15 |

The lower DP8 index (`CX0`) is the higher-weight field, so it is the shifted operand. Wire this crossed, not adjacent — it is the cross-boundary connection between `disp_array` pairs.

### Per-level shifts and the field weights

The shift at each level applies the radix weight that separates the two operands being merged. The amounts are fixed; only the enables are per-mode:

```systemverilog
localparam int SH0 = 8;   // L0, gated by sel_shift_i[0]
localparam int SH1 = 4;   // L1, gated by sel_shift_i[1]
localparam int SH2 = 8;   // L2, gated by sel_shift_i[2]
```

The three enables in `sel_shift_i` follow the operand split, reproducing the `2^0…2^20` field weights in `modes.xlsx`:

| Enable           | Level    | Set when            |
| ---------------- | -------- | ------------------- |
| `sel_shift_i[0]` | L0 `<<8` | A is 16-bit         |
| `sel_shift_i[1]` | L1 `<<4` | B is at least 8-bit |
| `sel_shift_i[2]` | L2 `<<8` | B is 16-bit         |

For example the testbench drives `sel_shift = 3'b000` for the R8R4 modes (no weighting), `3'b010` for R8R8 (only L1 `<<4`), `3'b011` for R16R8 (L0 `<<8` + L1 `<<4`), and `3'b111` for the R16R16 / C16C16 modes (all three). When an enable is `0` the level still exists — its `shift_n` just sign-extends instead of shifting, so the two operands add at equal weight.

### Width growth and the taps

**Value bits per level (pure arithmetic, no guard bit).** How many bits each mode's result actually occupies at each level it passes through — magnitude + sign (**bold** = the tap that mode reads, `–` = never reached). A tap's closed form is `Pa + Pb + log₂K` (real), `+ 1` for complex. The R16R16 modes (8, 9, 12) share their L0/L1 values with R16R8 (3, 7): B's high byte enters only at **L2** (`sel_shift[2]`), so through L0/L1 an R16R16 datapath is byte-for-byte identical to R16R8.

| Mode | Prec   | Tap | L0     | L1     | L2     | L3     |
| ---- | ------ | --- | ------ | ------ | ------ | ------ |
| 1    | R8R4   | L0  | **16** | –      | –      | –      |
| 2    | R8R8   | L1  | 16     | **20** | –      | –      |
| 3    | R16R8  | L1  | 23     | **27** | –      | –      |
| 5    | R8R4   | L2  | 16     | 16     | **17** | –      |
| 6    | R8R8   | L3  | 16     | 20     | 21     | **21** |
| 7    | R16R8  | L2  | 23     | 27     | **28** | –      |
| 8    | R16R16 | L3  | 23     | 27     | 35     | **36** |
| 9    | R16R16 | L2  | 23     | 27     | **35** | –      |
| 10   | C8C8   | L1  | 16     | **20** | –      | –      |
| 11   | C8C8   | L2  | 16     | 20     | **21** | –      |
| 12   | C16C16 | L2  | 23     | 27     | **35** | –      |

**Worst case per level.** Left: the worst over **every** mode that reaches the level — sizes the **node** that feeds the next level. Right: the worst over only the modes that **exit** (read their tap) at the level — sizes the exported **tap**.

| Level | Worst — all modes through | Worst — modes exiting here |
| ----- | ------------------------- | -------------------------- |
| L0    | 23 (modes 3, 7, 8, 9, 12) | 16 (mode 1)                |
| L1    | 27 (modes 3, 7, 8, 9, 12) | 27 (mode 3)                |
| L2    | 35 (modes 8, 9, 12)       | 35 (modes 9, 12)           |
| L3    | 36 (mode 8)               | 36 (mode 8)                |

**Real architectural widths.** Node widths are just `prev + shift` — every compressor runs `EXT = 0`:

```systemverilog
localparam int L0_WIDTH = DP8_WIDTH + SH0;      // 20 + 8  = 28
localparam int L1_WIDTH = L0_WIDTH + SH1;       // 28 + 4  = 32
localparam int L2_WIDTH = L1_WIDTH + SH2;       // 32 + 8  = 40
localparam int L3_WIDTH = L2_WIDTH;             // 40 + 0  = 40
```

| Level | operand width in (`prev + shift`) | CPR `EXT` | node width out |
| ----- | --------------------------------- | --------- | -------------- |
| DP8   | —                                 | —         | 20             |
| L0    | 20 + **8** = 28                   | **0**     | **28**         |
| L1    | 28 + **4** = 32                   | **0**     | **32**         |
| L2    | 32 + **8** = 40                   | **0**     | **40**         |
| L3    | 40 + **0** = 40                   | **0**     | **40**         |

The DP8 already delivers a sign-consistent 20-bit pair (16-bit value + **4 guard bits**), and that headroom is enough for the whole tree: at every level `node − worst-through-value ≥ 3`, comfortably above the 2 guard bits a 4:2 needs. So no compressor takes extra `EXT` growth, and each node is simply the previous node plus that level's shift. L3 is special — it has **no** `shift_n` and **no** `ext_n`, because its two L2 operands are already the same `L2_WIDTH`; they feed the compressor directly:

```systemverilog
logic [L2_WIDTH-1:0] l3_cpr_in [0:3];
assign l3_cpr_in[0] = l2_sum[0];
assign l3_cpr_in[1] = l2_carry[0];
assign l3_cpr_in[2] = l2_sum[1];
assign l3_cpr_in[3] = l2_carry[1];

cpr_w_n #(.IN_WIDTH(L2_WIDTH), .IN_SIZE(4), .EXT(0), .IS_SIGNED(1'b1)) cpr_w_n_l3_i (
    .in_i(l3_cpr_in), .sum_o(l3_sum_w), .carry_o(l3_carry_w)
);
```

**Node vs tap.** The full node width above feeds the *next* level and is sized for the worst intermediate across all modes. The tap exported to the accumulator is narrower — it only holds the modes that actually *read* that level. Each tap is the output of a 4:2 compressor, so its minimum sign-consistent width is that mode's value + 2 compressor guard bits; the tap is the **low slice** of the node:

```systemverilog
assign l0_sum_o[n]   = l0_sum_q[n][L0_TAP_WIDTH-1:0];   // low 18 of 28
assign l1_sum_o[j]   = l1_sum[j][L1_TAP_WIDTH-1:0];     // low 29 of 32
assign l2_sum_o[k]   = l2_sum[k][L2_TAP_WIDTH-1:0];     // low 37 of 40
assign l3_sum_o      = l3_sum_w[L3_TAP_WIDTH-1:0];      // low 38 of 40
```

| Level | node | tap    | tap = widest reading-mode value + 2 |
| ----- | ---- | ------ | ----------------------------------- |
| L0    | 28   | **18** | mode 1 (R8R4): 16 + 2               |
| L1    | 32   | **29** | mode 3 (R16R8): 27 + 2              |
| L2    | 40   | **37** | modes 9/12 (R16R16): 35 + 2         |
| L3    | 40   | **38** | mode 8 (R16R16): 36 + 2             |

The high node bits above the tap only exist so the next level receives full precision; the accumulator sign-extends each tap into its lane. These tap widths are verified sign-consistent across all 11 modes under corner-biased operands (most-negative / max-positive lanes).

### Pipelining (the L0 register)

L0 is the **only** registered stage — the single pipeline boundary inside `pe_array`. Two `reg_n` banks capture the L0 nodes at their full 28-bit width (not the narrow tap), one for sum and one for carry:

```systemverilog
reg_n #(.WIDTH(L0_WIDTH), .SIZE(NUM_L0)) reg_n_l0_sum_i (
    .clk_i(clk_i), .rst_ni(rst_ni), .d_i(l0_sum), .q_o(l0_sum_q)
);
reg_n #(.WIDTH(L0_WIDTH), .SIZE(NUM_L0)) reg_n_l0_carry_i (
    .clk_i(clk_i), .rst_ni(rst_ni), .d_i(l0_carry), .q_o(l0_carry_q)
);
```

Registering at full 28-bit width matters: the R16 modes' `<<8` intermediate must reach L1 without truncation, so `l0_sum_q`/`l0_carry_q` feed L1 at full precision while only their low 18 bits leave as the L0 tap. L1, L2, and L3 are all combinational — one clock through the whole tree.

### Reading a mode's result (which level / tap)

A mode reads its outputs at the level whose node count equals its parallel-output count: 8 → L0, 4 → L1, 2 → L2, 1 → L3. The testbench encodes this mapping in `TAP_LEVEL`, and its `resolve_tap` reads that level's tap by summing the carry-save pair (`$signed(sum) + $signed(carry)`):

| Mode | Precision | Tap level |
| ---- | --------- | --------- |
| 1    | R8R4      | L0        |
| 2    | R8R8      | L1        |
| 3    | R16R8     | L1        |
| 5    | R8R4      | L2        |
| 6    | R8R8      | L3        |
| 7    | R16R8     | L2        |
| 8    | R16R16    | L3        |
| 9    | R16R16    | L2        |
| 10   | C8C8      | L1        |
| 11   | C8C8      | L2        |
| 12   | C16C16    | L2        |

A complex output occupies **two adjacent nodes** (`Re` then `Im`), so it reads one level *shallower* than a real result of the same count — mode 10 (2 complex results) at L1, modes 11/12 (1 complex result) at L2. Reading them a level deeper would sum `Re + Im` into one node instead of keeping the parts separate.

Source: [pe_array.sv](../../rtl/pe_array.sv) — Testbench: [tb_pe_array.sv](../../tb/tb_pe_array.sv) — Diagram: [pe_array](../../doc/diagrams/pe_array.excalidraw)
