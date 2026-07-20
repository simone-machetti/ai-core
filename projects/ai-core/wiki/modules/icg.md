# Integrated Clock Gate

`icg` — an integrated clock-gating cell: passes the clock to a block while enabled and holds it low while disabled, so a block can be frozen without stopping the free-running clock. Synthesis maps it to the ASAP7 `ICGx1` standard cell; simulation uses a behavioural latch-and-AND model.

## Purpose

Per-block clock gating. Driving `en_i` low stops `clk_o`, so the registers downstream hold their state and burn no dynamic power, while the source clock keeps running for the rest of the design. The enable is captured on the clock's low phase so `clk_o` never glitches when `en_i` changes mid-cycle. In the N×N PE grid (`top_NxN`) each PE has its own `icg`, driven by that PE's `clk_gate` bit, so an idle PE can be stopped independently.

## Parameters

None.

## Interface

| Signal  | Dir | Width | Description                                   |
| ------- | --- | ----- | --------------------------------------------- |
| `clk_i` | in  | 1     | Free-running source clock.                    |
| `en_i`  | in  | 1     | Clock enable: `1` = pass, `0` = gate off.     |
| `clk_o` | out | 1     | Gated clock (`clk_i` when enabled, else `0`). |

## Instantiation

```systemverilog
icg icg_i (
    .clk_i(clk_i),
    .en_i (en),
    .clk_o(gated_clk)
);
```

## Internal logic

Two implementations of the same function, selected by `SYNTHESIS` — a macro the Slang frontend defines implicitly and the simulator does not, so each flow picks its own branch with no flag plumbing.

**Synthesis** — the ASAP7 integrated clock gate, instantiated directly. Scan enable is tied off:

```systemverilog
ICGx1_ASAP7_75t_R icg_cell_i (
    .CLK (clk_i),
    .ENA (en_i),
    .SE  (1'b0),
    .GCLK(clk_o)
);
```

**Simulation** — the behavioural model, which keeps the RTL portable and technology independent:

```systemverilog
always_latch begin
    if (clk_i == 1'b0) begin
        clk_en = en_i;
    end
end
assign clk_o = clk_i & clk_en;
```

Sampling `en_i` only while `clk_i` is low means the AND gate's enable input is stable for the whole high pulse, so toggling `en_i` mid-cycle cannot chop `clk_o` into a runt pulse — the gate opens or closes cleanly between cycles.

Instantiating the library cell rather than letting synthesis infer the latch matters for two reasons. Clock-tree synthesis recognizes an `ICGx1` as a clock gate and balances it as one, instead of treating a latch and an AND as ordinary logic sitting in the clock path. And Yosys has no liberty-driven latch mapper — `dfflibmap` covers flip-flops only — so the inferred `$_DLATCH_N_` reached the netlist unmapped, leaving a cell with no Verilog model and no area. The flow now also applies the platform latch map (`cells_latch_R.v`) after `dfflibmap`, so any design that does infer a latch gets a real cell; this module no longer needs it. Cell area is 0.26244 µm², against 0.24786 µm² for the three-gate inferred version that was missing its latch.

Source: [icg.sv](../../rtl/icg.sv) · used by [top_NxN](../architectures/top_NxN.md), [top_NxN_sqr](../architectures/top_NxN_sqr.md) · measured in [Synthesis Area](../experiments/syn_area.md)
