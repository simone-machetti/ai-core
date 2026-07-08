# Dispatch Array Testbench

## Purpose

`tb_disp_array` is the clocked self-checking testbench for [disp_array](../modules/disp_array.md), the operand router. For each of the 11 operating modes it drives the mode's dispatch control vectors, pushes random 256-bit `A`/`B` operands plus a directed ramp through the input registers, and checks all 16 DP8 `a`/`b` operands against an independent golden router model.

## Parameters

| Parameter  | Default | Description                                                                                                                |
| ---------- | ------- | -------------------------------------------------------------------------------------------------------------------------- |
| `NUM_RAND` | `500`   | Number of random 256-bit operand vectors driven per mode (a directed ramp vector is added after each mode's random batch). |

The DUT is instantiated with its defaults; the tb pins the shape with localparams `NUM_BLK=4`, `BLK_WIDTH=64`, `NUM_PAIR=8`, `NUM_DP8=16`, `A_DP8_WIDTH=64`, `B_DP8_WIDTH=32`, `B_ELEM_WIDTH=4` and does not override any DUT parameter.

## Run

```
make sim PROJECT=ai-core TOP_LEVEL=disp_array
```

Increase the random budget with `PARAMS="NUM_RAND=5000"`.

## What it checks

| Aspect   | Detail                                                                                                |
| -------- | ----------------------------------------------------------------------------------------------------- |
| Modes    | all 11 (control vectors — block selects + B-gate ops — taken from `doc/formulas/modes.xlsx`)          |
| Stimulus | `NUM_RAND` random 256-bit `A`/`B` operands + a directed ramp vector, per mode                         |
| Golden   | an independent router model: 4→1 block select, high/low B split, per-int4 gate (pass / zero / negate) |
| Coverage | every one of the 16 DP8 `a` outputs and 16 `b` outputs compared each cycle                            |

Any mismatch is **fatal** and dumps `activity.vcd`. The per-mode control vectors this testbench exercises are the reference for the eventual `pe_ctrl` decoder.

## How it checks

### Mode control vectors

Each mode is defined by four per-pair control arrays lifted from `modes.xlsx`: `SEL_A`/`SEL_B` pick which of the four 64-bit input blocks feeds each of the 8 pairs, and `CTR_L`/`CTR_H` are the gate ops for the low and high 32-bit halves of the selected B block. `set_controls` copies the row for the current mode onto the DUT inputs before the stimulus loop:

```systemverilog
task automatic set_controls(input int mi);
    for (int p = 0; p < NUM_PAIR; p++) begin
        sel_a[p] = SEL_A[mi][p];
        sel_b[p] = SEL_B[mi][p];
        ctr_l[p] = CTR_L[mi][p];
        ctr_h[p] = CTR_H[mi][p];
    end
endtask
```

### Stimulus generation

`rand_vec` fills the two 256-bit operands 32 bits at a time with `$urandom`. After the random batch, `ramp_vec` writes a directed pattern — `A` as an ascending byte ramp, `B` as an ascending int4 ramp — so every block/half/nibble carries a distinct, position-revealing value that would expose a swapped or shifted route a random draw could mask.

```systemverilog
task automatic ramp_vec;
    for (int by = 0; by < NUM_BLK*BLK_WIDTH/8;  by++) pe_in_a[by*8 +: 8] = by[7:0];
    for (int ni = 0; ni < NUM_BLK*BLK_WIDTH/4;  ni++) pe_in_b[ni*4 +: 4] = ni[3:0];
endtask
```

### The golden router model

`check` recomputes what each DP8 operand *should* be, straight from the raw 256-bit inputs and the mode's control row — it does not look at the DUT internals. For each pair `p` it selects the `A` and `B` blocks by `SEL_A`/`SEL_B`, duplicates the selected `A` block onto both DP8 lanes of the pair, and splits the selected `B` block into its high and low 32-bit halves, gating each half with `CTR_H`/`CTR_L`:

```systemverilog
oa    = int'(SEL_A[mi][p]) * BLK_WIDTH;
ob    = int'(SEL_B[mi][p]) * BLK_WIDTH;
a_sel = pe_in_a[oa +: BLK_WIDTH];
b_sel = pe_in_b[ob +: BLK_WIDTH];
a_exp[2*p+0] = a_sel;
a_exp[2*p+1] = a_sel;
b_exp[2*p+0] = gate32(b_sel[BLK_WIDTH-1:B_DP8_WIDTH], CTR_H[mi][p]);
b_exp[2*p+1] = gate32(b_sel[B_DP8_WIDTH-1:0],        CTR_L[mi][p]);
```

The gate itself is modelled by `gate32`, which reproduces the three B-gate ops per int4 element: `1` forces zero, `2` two's-complement negates each nibble, and everything else passes through.

```systemverilog
case (op)
    2'd1:    y = '0;
    2'd2:    for (int e = 0; e < NUM_B_ELEM; e++) y[e*B_ELEM_WIDTH +: B_ELEM_WIDTH] = (~x[e*B_ELEM_WIDTH +: B_ELEM_WIDTH]) + 4'd1;
    default: y = x;
endcase
```

### Drive/sample timing

`disp_array` registers its 256-bit inputs, so this is a clocked test. The loop drives fresh operands combinationally, advances one clock edge to latch them into the input registers, then waits `#1` before calling `check` so the combinational routing settles on the newly registered values:

```systemverilog
for (int t = 0; t < NUM_RAND; t++) begin
    rand_vec;
    @(posedge clk_i);
    #1;
    check(mi);
end
```

The controls are combinational routing selects, so the golden reads the same `pe_in_a`/`pe_in_b` that were just registered — one clock of input-register latency, no deeper pipeline. Two clocks of reset (`rst_ni` low) precede the mode sweep.

### Compare and report

`check` compares all 16 `a_dp8` outputs against `a_exp` and all 16 `b_dp8` against `b_exp` with `!==` (so X/Z also fail). The first mismatch calls `$dumpoff`, prints the mode, DP8 index, and expected/got values, and `$fatal`s. A mode that survives its whole random batch plus the ramp prints `mode N: PASS`, and after all 11 modes the tb prints the final all-passed banner and `$finish`.

Source: [tb_disp_array.sv](../../tb/tb_disp_array.sv) — DUT: [disp_array](../modules/disp_array.md)
