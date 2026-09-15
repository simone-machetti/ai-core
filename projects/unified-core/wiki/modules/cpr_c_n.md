# Cascade Compressor N

`cpr_c_n` — Parameterized N-to-2 carry-save compressor, serial-cascade build: reduces `IN_SIZE` `IN_WIDTH`-bit inputs to two rows whose arithmetic sum equals the sum of all inputs, in minimal area.

## Purpose

Sums a group of values into redundant carry-save form (`sum_o`, `carry_o`) with the smallest area: the inputs are absorbed one at a time through a single reused 3:2 stage laid out as a serial cascade, so latency grows linearly with `IN_SIZE`. It shares its interface exactly with the Wallace-tree build [cpr_w_n](./cpr_w_n.md) — pick between them purely on the min-area (cascade) vs max-throughput (Wallace) tradeoff; both produce an identically-formatted `(sum, carry)` pair.

## Parameters

| Parameter   | Default           | Description                                            |
| ----------- | ----------------- | ------------------------------------------------------ |
| `IN_WIDTH`  | `8`               | Bit width of each input word.                          |
| `IN_SIZE`   | `8`               | Number of input words to compress.                     |
| `EXT`       | `$clog2(IN_SIZE)` | Extra headroom bits added on top of `IN_WIDTH`.        |
| `IS_SIGNED` | `1'b1`            | Input extension: `1` = sign-extend, `0` = zero-extend. |

`OUT_WIDTH` (derived `localparam`) `= IN_WIDTH + EXT` — the width of both output rows and of every internal cascade row. A second derived `localparam`, `NSTAGE = (IN_SIZE >= 2) ? (IN_SIZE - 2) : 0`, is the number of cascade stages. The default `EXT = $clog2(IN_SIZE)` is the minimum headroom that keeps the running sum from wrapping; callers that later sign-extend and re-align the pair pass one extra **guard bit**, `EXT = $clog2(IN_SIZE) + 1` — see [Sign consistency](#sign-consistency). `IS_SIGNED` is a **compile-time** parameter because a compressor's signedness is fixed by its position in the datapath, never switched at runtime.

## Interface

| Signal    | Dir | Width                  | Description                                                             |
| --------- | --- | ---------------------- | ----------------------------------------------------------------------- |
| `in_i`    | in  | `IN_SIZE` × `IN_WIDTH` | Input words — unpacked array `[0:IN_SIZE-1]`.                           |
| `sum_o`   | out | `OUT_WIDTH`            | Carry-save sum row.                                                     |
| `carry_o` | out | `OUT_WIDTH`            | Carry-save carry row; `sum_o + carry_o` = Σ inputs (mod 2^`OUT_WIDTH`). |

## Instantiation

```systemverilog
cpr_c_n #(
    .IN_WIDTH (10),
    .IN_SIZE  (8),
    .EXT      ($clog2(8) + 1),   // guard bit for sign-consistent re-alignment
    .IS_SIGNED(1'b1)
) cpr_c_n_i (
    .in_i   (in),      // logic [9:0] in [0:7]
    .sum_o  (sum),     // logic [13:0]
    .carry_o(carry)    // logic [13:0]
);
```

## Internal logic

Purely combinational — no clock, no storage. Every input is first widened to `OUT_WIDTH`, a running `(sum, carry)` pair is seeded from the first two words, and the rest are folded in one per stage down a linear cascade of 3:2 compressors.

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

The reduction state is two `OUT_WIDTH`-wide arrays, `s[0:NSTAGE]` (running sum) and `c[0:NSTAGE]` (running carry) — one `(s[k], c[k])` pair per cascade index `k`.

### Reduction structure

The cascade is seeded, then extended one input at a time. Seeding exploits the fact that **any two numbers already form a carry-save pair**: `s[0]` and `c[0]` are simply the first two extended inputs, so no adder is spent on them. (For the degenerate `IN_SIZE == 1` case there is nothing to pair, so `c[0]` is zeroed.)

```systemverilog
if (IN_SIZE == 1) begin : gen_seed_one
    assign s[0] = ext_in[0]; assign c[0] = '0;
end else begin : gen_seed_two
    assign s[0] = ext_in[0]; assign c[0] = ext_in[1];
end
```

Each subsequent stage `k` absorbs exactly one more input, `ext_in[k+1]`, by 3:2-compressing it with the current running pair. The stage is an `OUT_WIDTH`-wide row of [fa](./fa.md) cells; its sum bits become the new `s[k]` and its carry bits, shifted up one position, become the new `c[k]`:

```systemverilog
for (k = 1; k <= NSTAGE; k++) begin : gen_stage
    logic [OUT_WIDTH-1:0] cout;
    for (b = 0; b < OUT_WIDTH; b++) begin : gen_bit
        fa fa_i (
            .in_0_i(s[k-1][b]), .in_1_i(c[k-1][b]), .cin_i(ext_in[k+1][b]),
            .sum_o (s[k][b]),   .cout_o(cout[b])
        );
    end
    assign c[k] = cout << 1;
end
```

Each `fa` obeys `a + b + cin = sum + 2·cout`, so a stage preserves `value(s) + value(c) + value(input)` into the next `(s, c)` pair; the `cout << 1` restores the carry's weight-2 position, exactly as in the Wallace build — the two designs differ only in how the 3:2 cells are wired (a serial chain here, parallel layers there). Starting from the 2-input seed and adding one input per stage, `NSTAGE = IN_SIZE − 2` stages consume inputs `ext_in[2] … ext_in[IN_SIZE-1]`, so all `IN_SIZE` inputs are folded in. This is what makes it **min-area / max-latency**: one reused 3:2 row per extra input, chained end to end.

### Carry-save output / EXT and the guard bit

The result is just the tail of the cascade:

```systemverilog
assign sum_o   = s[NSTAGE];
assign carry_o = c[NSTAGE];
```

When `IN_SIZE <= 2`, `NSTAGE = 0` and the outputs are the seed itself — a single input (with `carry_o = 0`) or the two-input pair passed straight through. `EXT` sets `OUT_WIDTH` and therefore the headroom carried down the cascade. Summing `IN_SIZE` words can grow the magnitude by up to a factor of `IN_SIZE`, i.e. by `clog2(IN_SIZE)` bits, so extending each input by `EXT = clog2(IN_SIZE)` before reduction guarantees the true sum still fits in `OUT_WIDTH` bits. That matters because each carry row is formed as `cout << 1`: the shift pushes the top carry bit out of the `OUT_WIDTH` field, so each stage only preserves the running sum **modulo 2^`OUT_WIDTH`**. With enough headroom that dropped bit lies above the true sign region and the mod-2^`OUT_WIDTH` result equals the true signed sum.

### Sign consistency

`EXT = clog2(IN_SIZE)` is exactly enough for `sum_o + carry_o` to equal the true sum **modulo 2^`OUT_WIDTH`** — correct if you immediately add the two rows in one `OUT_WIDTH` adder. It is *not* enough to treat the two rows as independent signed numbers: with the true sum occupying the full signed range, the pair's MSB is a live data bit, so `sum_o` and `carry_o` interpreted separately can sum to the value ± 2^`OUT_WIDTH` (a hidden wrap), and sign-extending each row on its own would carry that wrap forward incorrectly.

One extra **guard bit**, `EXT = clog2(IN_SIZE) + 1`, keeps the true sum's magnitude below 2^(`OUT_WIDTH`−1), so the top bit of the field is a spare copy of the sign rather than data. That margin guarantees the cascade never leaves the pair wrapped: `sum_o` and `carry_o` are each well-formed two's-complement `OUT_WIDTH` numbers whose full-integer sum equals the true value exactly. The pair is then **sign-consistent** — you can sign-extend `sum_o` and `carry_o` independently to any wider width and re-add them and still get the right answer, which is what a caller needs when it sign-extends and shifts a carry-save pair into place before a later reduction. `IS_SIGNED` must match the datapath's signedness so that `ext_n` fills the guard region with the correct sign, keeping the whole chain consistent.

Source: [cpr_c_n.sv](../../rtl/cpr_c_n.sv) — Testbench: [tb_cpr_c_n.sv](../../tb/tb_cpr_c_n.sv)
