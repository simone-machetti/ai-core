---
type: module
title: Wallace Compressor N
description: N-to-2 carry-save compressor, Wallace-tree build (maximal throughput).
resource: rtl/cpr_w_n.sv
---

# Wallace Compressor N

`cpr_w_n` — Parameterized N-to-2 carry-save compressor, Wallace-tree build: reduces `IN_SIZE` `IN_WIDTH`-bit inputs to two rows whose arithmetic sum equals the sum of all inputs, in logarithmic depth.

## Purpose

Sums a group of values into redundant carry-save form (`sum_o`, `carry_o`) with the lowest latency: the rows are compressed in parallel layers, giving `~log_1.5(IN_SIZE)` depth to maximize throughput. It shares its interface with the serial-cascade build [cpr_c_n](./cpr_c_n.md) — pick between them purely on the min-area (cascade) vs max-throughput (Wallace) tradeoff — and is the compressor used throughout the DP8 (the 8:2 per-weight reducers, each with a guard bit, and the 6:2 final reducer with `EXT = 0`).

## Parameters

| Parameter   | Default           | Description                                            |
| ----------- | ----------------- | ------------------------------------------------------ |
| `IN_WIDTH`  | `8`               | Bit width of each input word.                          |
| `IN_SIZE`   | `8`               | Number of input words to compress.                     |
| `EXT`       | `$clog2(IN_SIZE)` | Extra headroom bits added on top of `IN_WIDTH`.        |
| `IS_SIGNED` | `1'b1`            | Input extension: `1` = sign-extend, `0` = zero-extend. |

`OUT_WIDTH` (derived `localparam`) `= IN_WIDTH + EXT` — the width of both output rows and of every internal reduction row. The default `EXT = $clog2(IN_SIZE)` is the minimum headroom that keeps the running sum from wrapping; callers that later sign-extend and re-align the pair (like the DP) pass one extra **guard bit**, `EXT = $clog2(IN_SIZE) + 1` — see [Sign consistency](#sign-consistency). `IS_SIGNED` is a **compile-time** parameter because a compressor's signedness is fixed by its position in the datapath, never switched at runtime.

## Interface

| Signal    | Dir | Width                  | Description                                                             |
| --------- | --- | ---------------------- | ----------------------------------------------------------------------- |
| `in_i`    | in  | `IN_SIZE` × `IN_WIDTH` | Input words — unpacked array `[0:IN_SIZE-1]`.                           |
| `sum_o`   | out | `OUT_WIDTH`            | Carry-save sum row.                                                     |
| `carry_o` | out | `OUT_WIDTH`            | Carry-save carry row; `sum_o + carry_o` = Σ inputs (mod 2^`OUT_WIDTH`). |

## Instantiation

```systemverilog
cpr_w_n #(
    .IN_WIDTH (10),
    .IN_SIZE  (8),
    .EXT      ($clog2(8) + 1),   // guard bit for sign-consistent re-alignment
    .IS_SIGNED(1'b1)
) cpr_w_n_i (
    .in_i   (in),      // logic [9:0] in [0:7]
    .sum_o  (sum),     // logic [13:0]
    .carry_o(carry)    // logic [13:0]
);
```

## Internal logic

Purely combinational — no clock, no storage. Every input is first widened to `OUT_WIDTH`, then the `IN_SIZE` rows are reduced to two through a fixed tree of parallel 3:2 layers built entirely from generate loops.

### Input extension

The `EXT` extra bits are applied by [ext_n](./ext_n.md), which sign-extends (or zero-extends, per `IS_SIGNED`) every one of the `IN_SIZE` words from `IN_WIDTH` to `OUT_WIDTH`. When `EXT == 0` the extender is skipped and the inputs pass straight through:

```systemverilog
if (EXT == 0) begin : gen_no_ext
    for (i = 0; i < IN_SIZE; i++) begin : gen_pass
        assign ext_in[i] = in_i[i];
    end
end else begin : gen_ext
    ext_n #(.WIDTH(IN_WIDTH), .SIZE(IN_SIZE), .EXT(EXT), .IS_SIGNED(IS_SIGNED))
    ext_n_i (.in_i(in_i), .out_o(ext_in));
end
```

The extended words `ext_in` become the first row layer, `row[0][i]`. The reduction operates on `row[0:NUM_LAYERS][0:IN_SIZE-1]`, an `OUT_WIDTH`-wide 2-D array where index `l` is the layer and the second index is the row within that layer.

### Reduction structure

The tree shape is fixed at elaboration by three helper functions that model the 3:2 reduction ratio without building any hardware:

```systemverilog
function automatic int next_rows(input int n);   // rows after one layer
    return (n / 3) * 2 + (n % 3);
endfunction
function automatic int num_layers(input int n);  // layers until 2 rows remain
    int cnt; cnt = 0;
    while (n > 2) begin n = next_rows(n); cnt = cnt + 1; end
    return cnt;
endfunction
function automatic int rows_at(input int n0, input int layer); ... // rows entering `layer`
```

`next_rows` captures the core idea: split the `n` current rows into `n/3` disjoint groups of three plus `n%3` (0, 1, or 2) leftovers; each group of three collapses to two, and the leftovers pass through, so `n` becomes `(n/3)*2 + (n%3)`. Iterating this until `n <= 2` gives `NUM_LAYERS = num_layers(IN_SIZE)`. For example `IN_SIZE = 8` reduces `8 → 6 → 4 → 3 → 2`, so `NUM_LAYERS = 4` — the ratio shrinks the row count by ~1.5× per layer, hence the `~log_1.5(IN_SIZE)` depth.

Each layer is one generate iteration. `rows_at(IN_SIZE, l)` recomputes how many rows `R` enter layer `l`; `NG = R/3` groups are compressed and `REM = R%3` rows are forwarded:

```systemverilog
for (l = 0; l < NUM_LAYERS; l++) begin : gen_layer
    localparam int R = rows_at(IN_SIZE, l), NG = R / 3, REM = R % 3;
    for (g = 0; g < NG; g++) begin : gen_group
        logic [OUT_WIDTH-1:0] cout;
        for (b = 0; b < OUT_WIDTH; b++) begin : gen_bit
            fa fa_i (
                .in_0_i(row[l][3*g+0][b]), .in_1_i(row[l][3*g+1][b]),
                .cin_i (row[l][3*g+2][b]),
                .sum_o (row[l+1][2*g+0][b]), .cout_o(cout[b])
            );
        end
        assign row[l+1][2*g+1] = cout << 1;
    end
    for (g = 0; g < REM; g++) begin : gen_rem
        assign row[l+1][2*NG + g] = row[l][3*NG + g];
    end
end
```

Within a group, an `OUT_WIDTH`-wide row of [fa](./fa.md) cells adds the three rows bit-by-bit. Each `fa` obeys `a + b + cin = sum + 2·cout`, so the two output rows of the group are the bitwise **sum** row (`row[l+1][2*g+0]`) and the **carry** row `cout << 1` (`row[l+1][2*g+1]`) — the left shift by one restores the carry's weight-2 position. The `REM` leftover rows (never 3, since full triples were consumed) copy forward unchanged into the tail slots of the next layer. After `NUM_LAYERS` layers exactly two rows remain.

### Carry-save output / EXT and the guard bit

The final two rows are the result, with a one-input degenerate case handled separately:

```systemverilog
if (IN_SIZE == 1) begin : gen_out_one
    assign sum_o = row[0][0]; assign carry_o = '0;   // no reduction: pass through
end else begin : gen_out_two
    assign sum_o = row[NUM_LAYERS][0]; assign carry_o = row[NUM_LAYERS][1];
end
```

`EXT` sets `OUT_WIDTH` and therefore the headroom carried through every layer. Summing `IN_SIZE` words can grow the magnitude by up to a factor of `IN_SIZE`, i.e. by `clog2(IN_SIZE)` bits, so extending each input by `EXT = clog2(IN_SIZE)` before reduction guarantees the true sum still fits in `OUT_WIDTH` bits. That matters because the carry row is formed as `cout << 1`: the shift pushes the top carry bit out of the `OUT_WIDTH` field, so each layer only preserves the running sum **modulo 2^`OUT_WIDTH`**. With enough headroom that dropped bit lies above the true sign region and the mod-2^`OUT_WIDTH` result equals the true signed sum.

### Sign consistency

`EXT = clog2(IN_SIZE)` is exactly enough for `sum_o + carry_o` to equal the true sum **modulo 2^`OUT_WIDTH`** — correct if you immediately add the two rows in one `OUT_WIDTH` adder. It is *not* enough to treat the two rows as independent signed numbers: with the true sum occupying the full signed range, the pair's MSB is a live data bit, so `sum_o` and `carry_o` interpreted separately can sum to the value ± 2^`OUT_WIDTH` (a hidden wrap), and sign-extending each row on its own would carry that wrap forward incorrectly.

One extra **guard bit**, `EXT = clog2(IN_SIZE) + 1`, keeps the true sum's magnitude below 2^(`OUT_WIDTH`−1), so the top bit of the field is a spare copy of the sign rather than data. That margin guarantees the reduction never leaves the pair wrapped: `sum_o` and `carry_o` are each well-formed two's-complement `OUT_WIDTH` numbers whose full-integer sum equals the true value exactly. The pair is then **sign-consistent** — you can sign-extend `sum_o` and `carry_o` independently to any wider width and re-add them and still get the right answer. This is precisely why the DP instantiates the per-weight reducers with `.EXT($clog2(LANES) + 1)`: it sign-extends and shifts each column's `(sum, carry)` pair into place before the final reduction. `IS_SIGNED` must match the datapath's signedness so that `ext_n` fills the guard region with the correct sign, keeping the whole chain consistent.

Source: [cpr_w_n.sv](../../rtl/cpr_w_n.sv) — Testbench: [tb_cpr_w_n.sv](../../tb/tb_cpr_w_n.sv)
