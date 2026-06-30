# sqr_s_5_bit_v1 — Optimized Signed 5-bit Squarer (Generated with CLAUDE Code)

## Overview

`sqr_s_5_bit_v1` computes the square of a 5-bit 2's-complement signed integer. It is a flat, single-module implementation with no subcomponent instantiation and no intermediate logic signals. Every output bit is expressed as a minimized Boolean function of the five raw input bits, derived by Karnaugh-map minimization over the full 32-entry truth table.

## Interface

| Port    | Direction | Width | Description                                      |
|---------|-----------|-------|--------------------------------------------------|
| `in_i`  | input     | 5     | Signed 2's-complement operand, range [−16, 15]   |
| `out_o` | output    | 9     | Unsigned square result, range [0, 256]           |

### Bit assignment

```
in_i  = { s, a3, a2, a1, a0 }
         s  = sign bit (in_i[4])
         a3..a0 = lower four bits (in_i[3:0])
```

## Output bit equations

### out_o[4:0] — sign-independent bits

The lower five output bits depend only on the raw lower bits `a3..a0`, with no contribution from `s`. The formulas are algebraically identical to those in `sqr_u_4_bit` applied to the raw (unmodified) bits:

| Bit       | Expression                                    |
|-----------|-----------------------------------------------|
| `out_o[0]` | `a0`                                         |
| `out_o[1]` | `0`                                          |
| `out_o[2]` | `a1 & ~a0`                                   |
| `out_o[3]` | `a0 & (a1 ^ a2)`                             |
| `out_o[4]` | `(a0 & (a2 ^ a3)) \| (a2 & ~a1 & ~a0)`      |

The sign-independence of these bits holds because the 2's-complement negation of `{a3,a2,a1,a0}` produces the same lower five bits of the square as the original unsigned value. The `s`-dependent correction terms cancel algebraically when expanded across all minterms.

### out_o[7:5] — sign-dependent bits

The upper three output bits require `s`. They were derived by exhaustive K-map minimization over the full 32-minterm space (two 4-variable planes, one per value of `s`).

#### out_o[5]

The formula splits on `a0`:

- **`a0 = 0`:** The result is sign-independent: `a1 & (a3 ^ a2)`. Squaring an even-magnitude operand produces the same bit-5 regardless of sign.
- **`a0 = 1`:** The result is `maj(a3, a2, a1) ^ s`, where `maj` is the 3-input majority function:

```
maj(a3, a2, a1) = (a3 & a2) | (a3 & a1) | (a2 & a1)
                = (a3 & (a2 | a1)) | (a2 & a1)
```

For positive inputs (`s = 0`), bit 5 equals `maj(a3, a2, a1)`. For negative inputs (`s = 1`), it equals the complement.

Combined equation:

```
out_o[5] = (~a0 & a1 & (a3 ^ a2))
         | ( a0 & (((a3 & (a2 | a1)) | (a2 & a1)) ^ s))
```

#### out_o[6]

Three prime implicant groups cover all minterms:

1. **Positive inputs with `a3 = 1`:** `~s & a3 & (~a2 | a1)`
   Mirrors `sqr_u_4_bit`'s formula for bit 6.

2. **Negative input `−8` (`s=1, a3=1, a2=0, a1=0, a0=0`):** `s & a3 & ~a2 & ~a1 & ~a0`
   Special case: (−8)² = 64 = `01000000`, bit 6 = 1. No other `a3 = 1` negative input sets bit 6.

3. **Negative inputs with `a3 = 0`:** `s & ~a3 & ((a1 ^ a0) | (a2 & a1))`
   Covers magnitudes 9–15 (with `a3 = 0`), whose squares have bit 6 set when neither `a1` and `a0` are equal nor `a2 & a1` holds.

```
out_o[6] = (~s & a3 & (~a2 | a1))
         | ( s & a3 & ~a2 & ~a1 & ~a0)
         | ( s & ~a3 & ((a1 ^ a0) | (a2 & a1)))
```

#### out_o[7]

Two prime implicant groups, one per sign:

- **Positive inputs:** `~s & a3 & a2`
  Mirrors `sqr_u_4_bit`'s formula; squares of 12–15 all have bit 7 set.
- **Negative inputs:** `s & ~a3 & (a2 ^ (a0 | a1))`
  Covers the magnitudes 12–15 reached from the negative half, which map to `a3 = 0` in the raw encoding and whose squared bit 7 is determined by `a2 ^ (a0 | a1)`.

```
out_o[7] = (~s & a3 & a2) | (s & ~a3 & (a2 ^ (a0 | a1)))
```

### out_o[8] — overflow flag

Set only for the input `−16` (binary `10000`), the single value whose magnitude (16) exceeds 4 bits. Its square is 256 = `100000000`, i.e., exactly `out_o[8] = 1` with all lower bits zero.

```
out_o[8] = s & ~a3 & ~a2 & ~a1 & ~a0
```

## Truth table (selected entries)

| `in_i` (decimal) | `in_i` (binary) | `out_o` (decimal) | `out_o` (binary)  |
|------------------:|:----------------|------------------:|:------------------|
|  15               | 0\_1111          |   225             | 0\_1110\_0001     |
|  10               | 0\_1010          |   100             | 0\_0110\_0100     |
|   1               | 0\_0001          |     1             | 0\_0000\_0001     |
|   0               | 0\_0000          |     0             | 0\_0000\_0000     |
|  −1               | 1\_1111          |     1             | 0\_0000\_0001     |
| −10               | 1\_0110          |   100             | 0\_0110\_0100     |
| −15               | 1\_0001          |   225             | 0\_1110\_0001     |
| −16               | 1\_0000          |   256             | 1\_0000\_0000     |

## Comparison with sqr_s_5_bit_v0

`sqr_s_5_bit_v0` (non-optimized variant) instantiates `ha` and `sqr_u_4_bit` submodules, using a ripple half-adder chain to recover the 4-bit magnitude before squaring. `sqr_s_5_bit_v1` eliminates both the subcomponent hierarchy and the intermediate magnitude signals by folding the sign correction directly into K-map-minimized output equations. This reduces the combinational depth on the critical path through bits 5–7 and avoids the carry chain latency of the magnitude recovery stage.

## Selection via add_sqr_s_5_bit_array

Pass `SQR_TYPE=0` (the default) to `add_sqr_s_5_bit_array` to instantiate `sqr_s_5_bit_v0`. Pass `SQR_TYPE=1` to use `sqr_s_5_bit_v1` instead.
