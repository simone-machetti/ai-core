# NR4SD Radix-4 Testbench

## Purpose

`tb_nr4sd_r4` is the self-checking testbench for [nr4sd_r4](../modules/nr4sd_r4.md). The input space is tiny — `IN_WIDTH_B` nibble bits plus the carry-in — so the bench is **exhaustive**: every one of the `2^(IN_WIDTH_B+1)` `(b, c_in)` vectors is driven, which proves the recoding total instead of sampling it. On each vector it reconstructs the digit sum from the emitted codes and checks it against `signed(b) + c_in`, the defining property of the hybrid.

## Parameters

| Parameter    | Default | Description                                        |
| ------------ | ------- | -------------------------------------------------- |
| `IN_WIDTH_B` | `4`     | Bit width of the nibble `b` (forwarded to the DUT) |

## Run

```
make sim PROJECT=unified-core TOP_LEVEL=nr4sd_r4
```

## What it checks

| Property           | Check                                                                                                     |
| ------------------ | --------------------------------------------------------------------------------------------------------- |
| Reconstruction     | `Σ_j d_j · 4^j == signed(b) + c_in` — the low digits from the NR4SD⁺ codes, the top from the Booth window |
| Digit range        | every NR4SD⁺ digit in `{−1, 0, +1, +2}`, the Booth digit in `{−2 … +2}`                                   |
| Zero code          | `b = 0`, `c_in = 0` recodes to the all-zero bus — what `pe_nr4sd_bfp`'s AND-mask relies on                |
| Distinct encodings | under each carry-in, the `2^IN_WIDTH_B` encodings are pairwise distinct                                   |

Exhaustive sweep under both carry-ins; **fatal** on any mismatch; dumps `activity.vcd`.

## How it checks

### Exhaustive sweep

`sweep` walks every nibble value for one carry-in, checking each and recording its encoding; the main sequence runs it once per carry-in:

```systemverilog
task automatic sweep(input bit cin);
    for (int v = 0; v < NUM_VEC; v++) begin
        b_v = IN_WIDTH_B'(v);
        check(cin);
        seen[v] = {b_booth, b_nr4sd};
    end
    ...
endtask

sweep(1'b0);
sweep(1'b1);
```

For the default nibble that is 16 values × 2 carry-ins = **32 vectors**, the whole input space of the module.

### Decoding by value, not by wiring

`check` sets the carry-in, waits `#1` for the combinational logic to settle, and forms the golden `signed(b) + c_in` — the nibble is always read as signed and the carry adds one. The DUT side is reconstructed from its codes: each NR4SD⁺ code is looked up in the cell's table, and the Booth window is decoded by Booth's **own rule** rather than compared against the bits `nr4sd_r4` happens to wire out, so any window that means the right digit is accepted:

```systemverilog
function automatic longint booth_digit(input logic [SEL_WIDTH-1:0] w);
    booth_digit = -2 * longint'(w[2]) + longint'(w[1]) + longint'(w[0]);
endfunction
```

```systemverilog
b_val   = longint'($signed(b_v)) + longint'(cin);
dig_sum = 0;
for (int j = 0; j < NUM_PAIR - 1; j++) begin
    d = nr4sd_digit(b_nr4sd[j*CODE_WIDTH +: CODE_WIDTH]);
    ...
    dig_sum += d * (longint'(1) << (2 * j));
end
d = booth_digit(b_booth);
...
dig_sum += d * (longint'(1) << (2 * (NUM_PAIR - 1)));
```

Each digit is range-checked as it is decoded — an NR4SD⁺ digit outside `{−1 … +2}` or a Booth digit outside `{−2 … +2}` is fatal on its own, before the sum is compared.

### Zero code and distinct encodings

Two properties go beyond the per-vector identity. The all-zero vector must produce the all-zero bus, `{b_booth, b_nr4sd} == '0`, because [pe_nr4sd_bfp](../modules/pe_nr4sd_bfp.md) quiets a gated lane by AND-masking the recoded buses and relies on the zero code being zero. And since `signed(b) + c_in` is injective in `b`, no two nibbles may share an encoding under the same carry-in — after each sweep the recorded encodings are compared pairwise:

```systemverilog
for (int v = 0; v < NUM_VEC; v++) begin
    for (int w = v + 1; w < NUM_VEC; w++) begin
        if (seen[v] === seen[w]) begin
            $error("DUPLICATE ENCODING c_in=%0d b=%0d and b=%0d share enc=%b",
                   cin, v, w, seen[v]);
            $fatal;
        end
    end
end
```

### Compare and reporting

All comparisons use `!==` / `===` (4-state exact match, so any `x`/`z` also trips them). On mismatch the VCD dump is stopped and the carry-in, nibble, both codes, the reconstructed sum and the expected value are printed before a fatal abort. If both sweeps complete, the run prints `nr4sd_r4: all 32 exhaustive tests (2 carry-ins x 16 values) PASSED!` and `$finish`es.

Result: **32/32 exhaustive vectors PASSED**, 0 mismatches.

Source: [tb_nr4sd_r4.sv](../../tb/tb_nr4sd_r4.sv) — DUT: [nr4sd_r4](../modules/nr4sd_r4.md)
