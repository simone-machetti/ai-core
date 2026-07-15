# Integrated Clock Gate

`icg` — an integrated clock-gating cell: passes the clock to a block while enabled and holds it low while disabled, so a block can be frozen without stopping the free-running clock.

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

The enable passes through a latch that is transparent while `clk_i` is low, then is ANDed with the clock:

```systemverilog
always_latch begin
    if (clk_i == 1'b0) begin
        clk_en <= en_i;
    end
end
assign clk_o = clk_i & clk_en;
```

Sampling `en_i` only while `clk_i` is low means the AND gate's enable input is stable for the whole high pulse, so toggling `en_i` mid-cycle cannot chop `clk_o` into a runt pulse — the gate opens or closes cleanly between cycles. This is the behavioural model of the standard-cell integrated clock gate; a real build maps it to the library ICG.

Source: [icg.sv](../../rtl/icg.sv)
