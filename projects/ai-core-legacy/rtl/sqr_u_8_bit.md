# sqr_u_8_bit — Unsigned 8-bit Squarer

## 1. Interface

| Port    | Direction | Width | Description            |
|---------|-----------|-------|------------------------|
| `in_i`  | input     | 8     | Unsigned operand A     |
| `out_o` | output    | 16    | Unsigned result P = A² |

The module is purely combinational (no clock, no reset).

---

## 2. Mathematical Basis

Let A be an 8-bit unsigned integer with bit decomposition:

```
A = Σ_{i=0}^{7}  a[i] · 2^i
```

Expanding the square:

```
A² = ( Σ_i a[i] · 2^i )²
   = Σ_i  a[i]²  · 2^(2i)            ← diagonal terms
   + 2 · Σ_{i<j} a[i]·a[j] · 2^(i+j) ← cross terms
```

Because each `a[i]` is a single bit, `a[i]² = a[i]`. Absorbing the factor of 2 into the exponent:

```
A² = Σ_i  a[i] · 2^(2i)                  ← diagonal: bit a[i] at position 2i
   + Σ_{i<j} (a[i] AND a[j]) · 2^(i+j+1) ← off-diagonal: AND at position i+j+1
```

This decomposition drives the entire design.

---

## 3. Partial Product Generation

### 3.1 Diagonal terms

Each `a[i]` is a single bit that contributes to the even output bit `2i` with no logic required — it is wired directly to the compression tree column for that bit position.

```
a0 → bit  0
a1 → bit  2
a2 → bit  4
a3 → bit  6
a4 → bit  8
a5 → bit 10
a6 → bit 12
a7 → bit 14
```

### 3.2 Off-diagonal terms

For every pair `(i, j)` with `i < j`, one AND gate computes `p[i][j] = a[i] & a[j]`. This term contributes to output bit `i + j + 1`. There are C(8, 2) = **28 AND gates** in total — exactly half the 64 that a general 8×8 multiplier would need for the same set of partial products, because squarer symmetry eliminates the `(j, i)` duplicate.

The 28 terms and their target bit positions:

| Term  | i | j | Bit `i+j+1` |
|-------|---|---|-------------|
| p01   | 0 | 1 | 2           |
| p02   | 0 | 2 | 3           |
| p03   | 0 | 3 | 4           |
| p12   | 1 | 2 | 4           |
| p04   | 0 | 4 | 5           |
| p13   | 1 | 3 | 5           |
| p05   | 0 | 5 | 6           |
| p14   | 1 | 4 | 6           |
| p23   | 2 | 3 | 6           |
| p06   | 0 | 6 | 7           |
| p15   | 1 | 5 | 7           |
| p24   | 2 | 4 | 7           |
| p07   | 0 | 7 | 8           |
| p16   | 1 | 6 | 8           |
| p25   | 2 | 5 | 8           |
| p34   | 3 | 4 | 8           |
| p17   | 1 | 7 | 9           |
| p26   | 2 | 6 | 9           |
| p35   | 3 | 5 | 9           |
| p27   | 2 | 7 | 10          |
| p36   | 3 | 6 | 10          |
| p45   | 4 | 5 | 10          |
| p37   | 3 | 7 | 11          |
| p46   | 4 | 6 | 11          |
| p47   | 4 | 7 | 12          |
| p56   | 5 | 6 | 12          |
| p57   | 5 | 7 | 13          |
| p67   | 6 | 7 | 14          |

---

## 4. Initial Column Occupancy

After placing all diagonal and off-diagonal terms, each output bit position has the following initial set of bits to be summed:

| Bit | Terms                            | Height |
|-----|----------------------------------|--------|
|  0  | `a0`                             | 1      |
|  1  | —                                | 0      |
|  2  | `a1`, `p01`                      | 2      |
|  3  | `p02`                            | 1      |
|  4  | `a2`, `p03`, `p12`               | 3      |
|  5  | `p04`, `p13`                     | 2      |
|  6  | `a3`, `p05`, `p14`, `p23`        | 4      |
|  7  | `p06`, `p15`, `p24`              | 3      |
|  8  | `a4`, `p07`, `p16`, `p25`, `p34` | 5      |
|  9  | `p17`, `p26`, `p35`              | 3      |
| 10  | `a5`, `p27`, `p36`, `p45`        | 4      |
| 11  | `p37`, `p46`                     | 2      |
| 12  | `a6`, `p47`, `p56`               | 3      |
| 13  | `p57`                            | 1      |
| 14  | `a7`, `p67`                      | 2      |
| 15  | —                                | 0      |

The column heights form a symmetric staircase peaking at bit 8 (height 5), which reflects the symmetric nature of the squarer's partial product array.

Bits 0, 1, and 13 require no adders. Bits 3 and 14 need only one adder once carries arrive from the left.

---

## 5. Compression Tree

The goal of the compression tree is to reduce every column to a single bit. The strategy is **carry-absorbing reduction**: when processing column `k`, all carries arriving from the lower-weight column `k-1` are absorbed together with the column's own terms. Every column therefore produces exactly one output bit plus some new carries sent rightward. By the time column 15 is reached, all carries are consumed and the result is directly readable — no final carry-propagate adder (CPA) is needed.

An FA reduces three bits to `{carry, sum}` (sum stays in the current column, carry moves to the next). An HA reduces two bits the same way. Both are inlined as combinational logic:

```
FA: sum  = x ^ y ^ z
    carry = (x & y) | (y & z) | (x & z)

HA: sum  = x ^ y
    carry = x & y
```

The following subsections trace each column through the compression tree. The notation `c<k>` means "carry leaving column `k` toward column `k+1`"; suffixes `a`, `b`, `c` distinguish multiple carries leaving the same column.

---

### Bit 0

No adder. `out_o[0] = a0` directly.

---

### Bit 1

No terms. `out_o[1] = 0` (hardwired).

---

### Bit 2 — 1 HA

Initial terms: `{a1, p01}` (height 2).

```
HA(a1, p01) → s2 = a1 ^ p01 → out_o[2]
              c2 = a1 & p01 → bit 3
```

---

### Bit 3 — 1 HA

Initial terms: `{p02}` (height 1). After absorbing `c2` from bit 2: height 2.

```
HA(p02, c2) → s3 = p02 ^ c2 → out_o[3]
              c3 = p02 & c2 → bit 4
```

---

### Bit 4 — 1 FA + 1 HA

Initial terms: `{a2, p03, p12}` (height 3). After absorbing `c3` from bit 3: height 4.

```
FA(a2, p03, p12) → s4a,  c4a     → bit 5
HA(s4a, c3)      → s4 = s4a ^ c3 → out_o[4]
                   c4 = s4a & c3 → bit 5
```

Carries to bit 5: `{c4a, c4}`.

---

### Bit 5 — 1 FA + 1 HA

Initial terms: `{p04, p13}` (height 2). After absorbing `{c4a, c4}`: height 4.

```
FA(p04, p13, c4a) → s5a,  c5a     → bit 6
HA(s5a, c4)       → s5 = s5a ^ c4 → out_o[5]
                    c5 = s5a & c4 → bit 6
```

Carries to bit 6: `{c5a, c5}`.

---

### Bit 6 — 2 FA + 1 HA

Initial terms: `{a3, p05, p14, p23}` (height 4). After absorbing `{c5a, c5}`: height 6.

```
FA(a3,  p05, p14) → s6a,  c6a      → bit 7
FA(p23, c5a, c5 ) → s6b,  c6b      → bit 7
HA(s6a, s6b)      → s6 = s6a ^ s6b → out_o[6]
                    c6 = s6a & s6b → bit 7
```

Carries to bit 7: `{c6a, c6b, c6}`.

---

### Bit 7 — 2 FA + 1 HA

Initial terms: `{p06, p15, p24}` (height 3). After absorbing `{c6a, c6b, c6}`: height 6.

```
FA(p06, p15, p24) → s7a,  c7a      → bit 8
FA(c6a, c6b, c6 ) → s7b,  c7b      → bit 8
HA(s7a, s7b)      → s7 = s7a ^ s7b → out_o[7]
                    c7 = s7a & s7b → bit 8
```

Carries to bit 8: `{c7a, c7b, c7}`.

---

### Bit 8 — 3 FA + 1 HA

Initial terms: `{a4, p07, p16, p25, p34}` (height 5). After absorbing `{c7a, c7b, c7}`: height 8.

```
FA(a4,  p07, p16) → s8a,  c8a     → bit 9
FA(p25, p34, c7a) → s8b,  c8b     → bit 9
FA(s8a, s8b, c7b) → s8c,  c8c     → bit 9
HA(s8c, c7)       → s8 = s8c ^ c7 → out_o[8]
                    c8 = s8c & c7 → bit 9
```

This is the widest column (8 inputs). Three FAs reduce it to 2 bits `{s8c, c7}`, which the HA then collapses to the final output bit and one carry.

Carries to bit 9: `{c8a, c8b, c8c, c8}`.

---

### Bit 9 — 3 FA

Initial terms: `{p17, p26, p35}` (height 3). After absorbing `{c8a, c8b, c8c, c8}`: height 7.

```
FA(p17, p26, p35) → s9a, c9a → bit 10
FA(c8a, c8b, c8c) → s9b, c9b → bit 10
FA(s9a, s9b, c8 ) → s9       → out_o[9]
                    c9       → bit 10
```

The third FA directly produces the output bit (no trailing HA needed because 7 terms collapse to exactly `{s9, c9}` via three FAs: 7 − 3·1 = 4 after pass 1, 4 − 1 = 3 after pass 2, 3 → 1 output + 1 carry after pass 3).

Carries to bit 10: `{c9a, c9b, c9}`.

---

### Bit 10 — 3 FA

Initial terms: `{a5, p27, p36, p45}` (height 4). After absorbing `{c9a, c9b, c9}`: height 7.

```
FA(a5,  p27, p36)  → s10a,  c10a → bit 11
FA(p45, c9a, c9b)  → s10b,  c10b → bit 11
FA(s10a, s10b, c9) → s10         → out_o[10]
                     c10         → bit 11
```

Carries to bit 11: `{c10a, c10b, c10}`.

---

### Bit 11 — 2 FA

Initial terms: `{p37, p46}` (height 2). After absorbing `{c10a, c10b, c10}`: height 5.

```
FA(p37, p46,  c10a) → s11a, c11a → bit 12
FA(s11a, c10b, c10) → s11        → out_o[11]
                      c11        → bit 12
```

Carries to bit 12: `{c11a, c11}`.

---

### Bit 12 — 2 FA

Initial terms: `{a6, p47, p56}` (height 3). After absorbing `{c11a, c11}`: height 5.

```
FA(a6,  p47, p56)   → s12a, c12a → bit 13
FA(s12a, c11a, c11) → s12        → out_o[12]
                      c12        → bit 13
```

Carries to bit 13: `{c12a, c12}`.

---

### Bit 13 — 1 FA

Initial terms: `{p57}` (height 1). After absorbing `{c12a, c12}`: height 3.

```
FA(p57, c12a, c12) → s13 → out_o[13]
                     c13 → bit 14
```

---

### Bit 14 — 1 FA

Initial terms: `{a7, p67}` (height 2). After absorbing `{c13}`: height 3.

```
FA(a7, p67, c13) → s14 → out_o[14]
                   c14 → bit 15
```

---

### Bit 15

No original terms. After absorbing `c14`: height 1.

```
out_o[15] = c14 (direct wire)
```

---

## 6. Why No Final CPA Is Needed

A conventional partial-product multiplier (or squarer) produces, after the compression tree, two residual rows — a sum vector and a carry vector — that must be added together by a carry-propagate adder to produce the final result. That final CPA contributes a significant share of the total area.

This design eliminates the CPA through the **carry-absorbing** compression strategy: at every column `k`, the incoming carries from column `k-1` are included in the reduction alongside the column's own terms. Each column therefore exhausts all of its inputs and produces exactly **one output bit**, with any remaining value forwarded as carries to column `k+1`. By the time the last column is processed, every carry has been consumed. There are no two residual rows; each `out_o[k]` is the final, correct bit for that weight.

The price paid is a combinational dependency chain that runs left-to-right through all 16 columns. Column `k` cannot be evaluated until the carries from column `k-1` are known, so the critical path traverses the full width of the result — a longer delay than a balanced Wallace tree followed by a fast CPA, but with strictly fewer cells.

---

## 7. Adder Count and Gate Budget

| Resource           | Count |
|--------------------|-------|
| AND gates (pij)    | 28    |
| Half adders (HA)   | 7     |
| Full adders (FA)   | 21    |

Compared to an 8-bit general multiplier using the same approach:
- AND gates: 28 vs 64 (factor-of-2 saving from symmetry)
- Adder count is also reduced because the column height profile is lower and more symmetric

Each FA inlines as 2 XOR + 3 AND/OR gates; each HA as 1 XOR + 1 AND gate. In terms of two-input gate equivalents the compression tree amounts to roughly 21 × 5 + 7 × 2 = 119 gate equivalents, plus 28 AND gates for the partial products, giving approximately **147 gate equivalents** before synthesis optimization. Post-synthesis, technology mapping and logic sharing (e.g., `c2 = a1 & p01 = a0 & a1 = p01`) will reduce this further.

---

## 8. Critical Path

The longest combinational path runs through the carry chain from bit 2 to bit 15:

```
a0, a1 → p01, c2 → c3 → (s4a, c4) → (s5a, c5) → (s6a/b, c6) →
(s7a/b, c7) → (s8a/b/c, c8) → c9 → c10 → c11 → c12 → c13 → c14 → out_o[15]
```

This is 14 carry-chain hops, each adding 2–3 gate delays (XOR + AND for the FA sum/carry). In contrast, a pure Wallace tree followed by a CPA would have roughly O(log N) compression stages plus O(log N) CPA stages, which is faster but requires more area. The carry-absorbing design is therefore the **area-minimal** choice at the cost of a longer timing path.
