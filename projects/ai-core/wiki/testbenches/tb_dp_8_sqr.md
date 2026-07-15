# Dot Product 8 (Square) Testbench

## Purpose

`tb_dp_8_sqr` verifies [dp_8_sqr](../modules/dp_8_sqr.md), the 8-lane carry-save **square-sum** core. It drives random and directed-corner vectors and checks a single property of the two 18-bit carry-save rows: that they *resolve* to a golden square-sum computed the same way. Because `dp_8_sqr` consumes **pre-centered** nibbles, the tb generates every nibble directly as a signed value in `[−8, 7]` — there is no `is_signed` and no `−8` bias (that is the dispatcher's job, out of scope here). The output is a sum of squares and therefore non-negative, so — unlike [tb_dp_8](./tb_dp_8.md) — there is **no sign-consistency check**.

## Parameters

| Parameter  | Default | Description                                                                                            |
| ---------- | ------- | ------------------------------------------------------------------------------------------------------ |
| `NUM_RAND` | `2000`  | Number of random vectors; after the random loop, all 8 extreme `{−8,+7}` combos + the zero corner run. |

The DUT has no overridable parameters; the tb pins the shape with localparams `LANES=8`, `WIDTH_A=8`, `WIDTH_B=4`, `NIB=4`, `OUT_WIDTH=18`.

## Run

```
make sim PROJECT=ai-core TOP_LEVEL=dp_8_sqr
```

Increase the random budget with `PARAMS="NUM_RAND=10000"`.

## What it checks

| Property | Check                                                                                               |
| -------- | --------------------------------------------------------------------------------------------------- |
| Resolve  | `sum_o + carry_o == Σ_k [ 16·(AH_k+b_k)² + (AL_k+b_k)² ]` (mod `2^18`; exact since `S_DP8 ≤ 34816`) |

There is no sign-consistency property: `S_DP8 ≥ 0`, so a single resolve check is complete. Any mismatch is **fatal**.

## How it checks

### Stimulus generation

Every nibble is a signed value in `[−8, 7]`, biased toward the extremes so the square-argument corner `−16` (square `256`, the 9th output bit) is hit within thousands of vectors. `rand_nib` returns roughly 20% most-negative (`−8`), 20% max-positive (`+7`), 60% uniform; `rand_vec` packs two nibbles into each `a_v` lane and one into `b_v`:

```systemverilog
function automatic logic [NIB-1:0] rand_nib;
    int p;
    p = $urandom % 5;
    if      (p == 0) rand_nib = N_MIN;   // -8
    else if (p == 1) rand_nib = N_MAX;   // +7
    else             rand_nib = NIB'($urandom);
endfunction

task automatic rand_vec;
    for (int k = 0; k < LANES; k++) begin
        a_v[k] = {rand_nib(), rand_nib()};   // {AH, AL}
        b_v[k] = rand_nib();
    end
endtask
```

After the random loop, a loop over `c = 0..7` drives all eight extreme combinations of `(AH, AL, b) ∈ {−8, +7}` with every lane pinned, then the all-zero corner:

```systemverilog
for (int c = 0; c < 8; c++) begin
    set_vec(c[2] ? N_MAX : N_MIN, c[1] ? N_MAX : N_MIN, c[0] ? N_MAX : N_MIN);
    check;
end
set_vec(N_ZERO, N_ZERO, N_ZERO);
check;
```

The all-`−8` corner drives every square argument to `−16` → `256`, the maximum `S_DP8 = 34816`.

### The golden reference

The expected value is a wide `longint` accumulator, completely outside the DUT: each lane's two nibbles are sign-extracted, added to `b`, squared, and summed with the AH block weighted `16`. It never mimics the carry-save tree:

```systemverilog
exp = 0;
for (int k = 0; k < LANES; k++) begin
    ah   = longint'($signed(a_v[k][NIB +: NIB]));
    al   = longint'($signed(a_v[k][  0 +: NIB]));
    b    = longint'($signed(b_v[k]));
    s_ah = ah + b;
    s_al = al + b;
    exp += 16 * (s_ah * s_ah) + (s_al * s_al);
end
```

### Drive/sample timing

`dp_8_sqr` is purely combinational, so there is no clock. `check` drives the operands, waits `#1` for the logic to settle, then reads `sum`/`carry` in the same delta region.

### Compare and report

`check` truncates `sum + carry` to `OUT_WIDTH` (18) bits and compares against the golden `exp`; since `S_DP8 < 2^18` the comparison is exact. A mismatch calls `$dumpoff` and `$fatal`, stopping at the first bad vector with both values printed:

```systemverilog
res = sum + carry;
if (res !== OUT_WIDTH'(exp)) begin
    $error("MISMATCH exp=%0d got=%0d (sum=%0d carry=%0d)", exp, res, sum, carry); $fatal;
end
```

If every vector passes, the tb prints `dp_8_sqr: all N random + corner tests PASSED!` and calls `$finish`.

Source: [tb_dp_8_sqr.sv](../../tb/tb_dp_8_sqr.sv) — DUT: [dp_8_sqr](../modules/dp_8_sqr.md)
