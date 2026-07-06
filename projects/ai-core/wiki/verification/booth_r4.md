---
type: experiment
title: Booth Radix-4 Testbench
description: Self-checking testbench for booth_r4 — the weighted partial-product sum must equal a·b under all four signedness combinations.
resource: tb/tb_booth_r4.sv
---

# Booth Radix-4 Testbench

## Purpose

`tb_booth_r4` is the self-checking testbench for [booth_r4](../modules/booth_r4.md). It verifies that the radix-4 recoding is exact by checking that the weighted sum of the emitted partial products equals `a·b` for `NUM_RAND` random operand pairs plus directed corners, each replayed under all four per-operand signedness combinations.

## Parameters

| Parameter    | Default | Description                                              |
| ------------ | ------- | -------------------------------------------------------- |
| `IN_WIDTH_A` | `8`     | Bit width of the multiplicand `a` (forwarded to the DUT) |
| `IN_WIDTH_B` | `4`     | Bit width of the multiplier `b` (forwarded to the DUT)   |
| `NUM_RAND`   | `2000`  | Number of random `(a, b)` vectors                        |

## Run

```
make sim PROJECT=ai-core TOP_LEVEL=booth_r4
```

## What it checks

| Property              | Check                                                                                       |
| --------------------- | ------------------------------------------------------------------------------------------- |
| Weighted-sum identity | `Σ_i pp_o[i] · 4^i == a_val · b_val`                                                        |
| Signedness coverage   | every vector run under all four `is_signed_a_i × is_signed_b_i` combinations                |
| Extra partial product | the unsigned-`b` combinations exercise the top recoded digit (`PP_SIZE = IN_WIDTH_B/2 + 1`) |

`a_val`/`b_val` interpret `a`/`b` as signed or unsigned per the signedness inputs. Random vectors + directed corners; **fatal** on any mismatch; dumps `activity.vcd`.

## How it checks

### Stimulus generation

Each iteration of the main loop draws a fresh random operand pair, then hands off to `check_all` (see below). Only the low `IN_WIDTH_A`/`IN_WIDTH_B` bits of each `$urandom` word are kept:

```systemverilog
task automatic rand_vec;
    a_v = IN_WIDTH_A'($urandom);
    b_v = IN_WIDTH_B'($urandom);
endtask

for (int t = 0; t < NUM_RAND; t++) begin
    rand_vec;
    check_all;
end
```

After the random phase, directed corners drive the boundary encodings through the same `check_all` path — all-zero, max-positive `× max-positive`, min-negative `× min-negative`, the two mixed max/min pairs, and all-ones `× all-ones`:

```systemverilog
set_vec(A_ZERO, B_ZERO);       check_all;
set_vec(A_MAX_POS, B_MAX_POS); check_all;
set_vec(A_MIN_NEG, B_MIN_NEG); check_all;
set_vec(A_MAX_POS, B_MIN_NEG); check_all;
set_vec(A_MIN_NEG, B_MAX_POS); check_all;
set_vec(A_ALL_ONES, B_ALL_ONES); check_all;
```

The corner constants are the sign-boundary bit patterns: `A_MAX_POS = {1'b0, all-ones}` (largest positive), `A_MIN_NEG = {1'b1, all-zeros}` (most negative), with `B_*` the same for the `IN_WIDTH_B` width. These stress the sign bit and the extra top digit that appears when `b` is treated as unsigned.

### Signedness sweep

`booth_r4` is purely combinational, so the same applied `(a_v, b_v)` bit pattern can be reinterpreted under every signedness setting without redriving the operands. `check_all` replays the current vector under all four `is_signed_a × is_signed_b` combinations:

```systemverilog
task automatic check_all;
    check(1'b0, 1'b0);
    check(1'b0, 1'b1);
    check(1'b1, 1'b0);
    check(1'b1, 1'b1);
endtask
```

### Golden reference model

`check` is where the DUT is verified against an independently computed golden value. It sets the DUT's signedness inputs, waits `#1` for the combinational logic to settle, then interprets each operand as signed or unsigned per the *same* flags it fed the DUT — this is the reference input mapping:

```systemverilog
task automatic check(input bit sgn_a, input bit sgn_b);
    ...
    is_signed_a = sgn_a;
    is_signed_b = sgn_b;
    #1;
    a_val  = sgn_a ? longint'($signed(a_v)) : longint'($unsigned(a_v));
    b_val  = sgn_b ? longint'($signed(b_v)) : longint'($unsigned(b_v));
    prod   = a_val * b_val;
```

`prod` is the golden result: a full-precision `longint` product computed by SystemVerilog's own multiply, entirely independent of the DUT's recoding. The DUT side is reconstructed by summing its partial-product outputs, each weighted by its radix-4 place value `4^i = 2^(2i)`. Every `pp_o[i]` is sign-extended (`$signed`) because partial products are themselves signed values:

```systemverilog
    pp_sum = 0;
    for (int i = 0; i < PP_SIZE; i++) begin
        pp_sum += longint'($signed(pp[i])) * (longint'(1) << (2 * i));
    end
```

If the recoding is correct, this weighted sum reconstructs exactly `a_val · b_val`.

### Compare and reporting

The reconstructed `pp_sum` is compared against the golden `prod` with `!==` (4-state exact match, so any `x`/`z` also trips it). On mismatch the VCD dump is stopped and the operands, the golden product, and the reconstructed sum are printed before a fatal abort:

```systemverilog
    if (pp_sum !== prod) begin
        $dumpoff;
        $error("MISMATCH sgn_a=%0d sgn_b=%0d a=%0d b=%0d prod=%0d pp_sum=%0d",
               sgn_a, sgn_b, a_val, b_val, prod, pp_sum);
        $fatal;
    end
```

If the whole loop plus corners complete without a fatal, the run prints `booth_r4: all N random + corner tests PASSED!` and `$finish`es. There is no self-scoring beyond pass/fail: a single mismatch aborts the simulation.

Source: [tb_booth_r4.sv](../../tb/tb_booth_r4.sv) — DUT: [booth_r4](../modules/booth_r4.md)
