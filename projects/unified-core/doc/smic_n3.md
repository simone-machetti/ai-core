# SMIC N+3 vs ASAP7 — technology delta and PDK adaptation plan

Purpose: make the PE-matrix results obtained with ASAP7 comparable with, and usable for, designs targeting Huawei HiSilicon's current SMIC nodes. This page records what is publicly known about SMIC N+3, how it differs from the ASAP7 predictive PDK used by this flow, what those differences do to our numbers, and a staged plan to move the ASAP7 platform closer to the target.

## 1. Naming and scope

- **SMIC N+3** is the third generation of SMIC's 7 nm-class FinFET process. SemiAnalysis titles its teardown "SMIC N3"; TechInsights and the press call it "5 nm-class". By measured density it is a TSMC N6-class node. It is **not** a 3 nm node.
- Teardown vehicle: HiSilicon **Kirin 9030 Pro** (Huawei Mate 80 Pro), about 140 mm², prime core 2.75 GHz, Cortex-X2-class per-clock performance at about 4.5 W.
- **Huawei's AI accelerators (Ascend 910C, 950 series) are reported on SMIC N+2**, the previous 7 nm-class generation. N+3 is expected on the next Ascend generation. For a PE-matrix comparison the relevant target is therefore N+2 today and N+3 next; the two differ mainly in cell height (252 vs 228 nm) and local metal pitch (about 40 vs 32.5 nm).
- All SMIC numbers below are SemiAnalysis measurements (June 2026). TechInsights' public pages confirm the node but publish no dimensions; their earlier "inferred" 54 nm gate / 36 nm track values predate the measurement and are superseded.

## 2. Parameters side by side

ASAP7 values come from the PDK paper and design-rule manual in the local install and from the cell LEF; SMIC values from the teardown.

| Parameter                   | ASAP7 (7.5T, RVT)                               | SMIC N+3                                               | Delta                                        |
| --------------------------- | ----------------------------------------------- | ------------------------------------------------------ | -------------------------------------------- |
| Device                      | FinFET, 3 fins per device                       | FinFET, 2 fins per device (fin depopulation)           | SMIC narrower devices                        |
| Fin pitch                   | 27 nm (SAQP, 193i)                              | ~32 nm (SAQP, 193i), aspect ratio ~9.5                 |                                              |
| Gate length                 | 21 nm (20 drawn)                                | not public                                             |                                              |
| Contacted gate pitch (CPP)  | 54 nm (SADP)                                    | 57 nm                                                  | +6 %                                         |
| Cell height                 | 270 nm = 7.5 tracks × 36 nm                     | 228 nm = 5.7 tracks × 40 nm                            | −16 %                                        |
| Diffusion break             | double (DDB)                                    | single (SDB)                                           | SMIC saves one CPP per cell boundary         |
| Gate contact                | via MOL local interconnect                      | contact over active gate (COAG)                        |                                              |
| Local metal                 | M1–M3: 36 nm, EUV single exposure, 2-D routable | M0 32.5 nm SAQP, M1 38, M2 40, M3 44 nm SADP; DUV only | SMIC finer M0, coarser M2/M3, unidirectional |
| M1 : gate pitch ratio       | 36 : 54 = 2 : 3                                 | 38 : 57 = 2 : 3                                        | same                                         |
| Mid metal                   | M4–M5 48 nm, M6–M7 64 nm (SADP)                 | M4–M6 80–82 nm (single exposure)                       | SMIC 1.3–1.7× coarser                        |
| Upper metal                 | M8–M9 80 nm                                     | M7–M10 128 nm, M11 148 nm, M12 1.92 µm, M13 4.6 µm     |                                              |
| Metal layers                | 9 + Pad                                         | 13                                                     |                                              |
| Lithography                 | EUV for MOL, V0–V3, M1–M3; 193i elsewhere       | 193i immersion only, SAQP/SADP                         | different design-rule regime                 |
| Power delivery              | front side                                      | front side                                             | same                                         |
| Nominal supply              | 0.70 V                                          | not public                                             |                                              |
| Logic density (Bohr metric) | ~81 MTr/mm² (computed, see below)               | 113.4 MTr/mm²                                          | SMIC 1.4×                                    |
| NAND2 footprint             | 4 CPP × 270 nm = 0.058 µm²                      | 3 CPP × 228 nm = 0.039 µm²                             | 0.67                                         |
| SRAM 6T HD bit cell         | not characterized in this flow                  | ~0.026 µm² (estimated)                                 |                                              |
| Corner used here            | TT, 0.70 V, 25 °C, NLDM                         | —                                                      |                                              |

ASAP7 density: NAND2xp33 is 0.216 × 0.270 µm (4 transistors, 68.6 MTr/mm²); the scan flop SDFHx1 is 1.35 × 0.270 µm (98.8 MTr/mm² assuming the conventional 36-transistor scan flop). Bohr weighting 0.6/0.4 gives about 81 MTr/mm². The flop transistor count is an assumption; the NAND2 figure is exact.

Track density per micron, the number that drives routing capacity:

| Role                       | ASAP7                              | SMIC N+3                           |
| -------------------------- | ---------------------------------- | ---------------------------------- |
| Local, cell-pin layers     | M1–M3: 27.8 each                   | M0 30.8, M1 26.3, M2 25.0, M3 22.7 |
| Mid, block routing         | M4–M5: 20.8 each; M6–M7: 15.6 each | M4–M6: 12.3 each                   |
| Upper, global              | M8–M9: 12.5 each                   | M7–M10: 7.8 each; M11: 6.8         |
| Sum above the local layers | 97.8                               | 75.2                               |

## 3. What the differences do to our results

**Cell level: ASAP7 is a fair N+2-class proxy with a uniform area bias.** Our cells are about 1.4–1.5× larger than N+3 cells for the same logic, from the taller cell and the double diffusion break. The PE variants are all full-adder, compressor, multiplexer and flop datapaths, so the bias is the same for every variant and **relative area comparisons transfer**. Absolute areas do not; use the scaling in section 4.

**Interconnect level: ASAP7 is optimistic, and this is where the matrix study lives.**

- ASAP7's mid stack has 1.3–1.7× the track density of SMIC's 80 nm M4–M6. The over-tile routing budget of the matrix would be smaller on N+3, by roughly a quarter in total tracks above the local layers.
- ASAP7 assumes 2-D routable EUV local layers. SMIC's SAQP/SADP layers are effectively unidirectional with restrictive end-of-line and cut rules; pin access and local routing are harder than ASAP7 models. The pin plans and edge congestion we measure are therefore lower bounds.
- SMIC has 13 layers against 9, with a real upper stack. A matrix on N+3 would route over hardened tiles on M7–M10 at 128 nm rather than on M6–M7 at 64 nm; fewer wires per micron but lower resistance per wire.

**Devices, timing and power do not transfer.** No public data exists for N+3 supply, drive current, FO4 delay, per-layer wire RC or via resistance. Ratios between variants (which is faster, which burns less at the same workload) transfer; absolute picoseconds and milliwatts do not.

**Power delivery is the same regime** (front-side rails and straps), so the tile/parent PDN scheme of the flow maps directly, with the strap layers moved as in section 5.

## 4. Working scaling factors

To present ASAP7 results in N+3-equivalent terms without touching the PDK:

| Quantity                                | Factor ASAP7 → N+3  | Basis                                                             |
| --------------------------------------- | ------------------- | ----------------------------------------------------------------- |
| Standard-cell area                      | 0.67–0.71, use 0.70 | NAND2 footprint ratio 0.67; Bohr density ratio 0.71               |
| Die area at equal utilization           | 0.70                | follows cell area; assumes routing closes at the same utilization |
| Local track capacity per µm             | 0.85–0.95           | 36 nm vs 38–44 nm pitches                                         |
| Mid-layer track capacity per µm         | 0.6–0.8             | 48/64 nm vs 80 nm                                                 |
| Total track capacity above local layers | 0.77                | 97.8 vs 75.2 tracks/µm                                            |
| Timing, power                           | not derivable       | no device data                                                    |

State every scaled number as an estimate with its factor. Do not scale timing or power.

## 5. Plan to move the ASAP7 platform toward SMIC N+3

The flow reads the whole technology through one root variable (`ASAP7_HOME`), and everything technology-specific is data: tech LEF, cell LEF, liberty, track file, PDN strategies, RC estimates, extraction rules, KLayout layer map. A variant platform tree is therefore a copy of the ASAP7 platform directory with edited data files, selected per run by pointing the root variable at it. The cell library itself cannot change, which fixes what is and is not reachable.

### Phase 0 — documentation only, no PDK change

Add the delta (sections 2–4) to the experiment pages and report an "N+3-equivalent" column for area using the 0.70 factor. Cost: none. This is the honest baseline and should be done regardless of the later phases.

### Phase 1 — SMIC-like metal stack (routing resource and layer roles)

Goal: make the interconnect resource, the layer count and the layer roles match N+3 so that block-level and matrix-level routing experiments are pessimistic in the right direction.

1. **Tech LEF.** Keep M1 and M2 unchanged: the standard cells have their pins and internal shapes on M1 and M2, so those pitches are frozen at 36 nm (they stand in for SMIC's M0/M1 at 32.5/38 nm, within 10 percent). Change every layer above, which no cell touches: M3 to 44 nm; M4, M5, M6 to 80 nm; M7, M8, M9 to 128 nm; add M10 at 128 nm, M11 at 148 nm, and two thick layers M12/M13 at about 2 and 4.6 µm, with the corresponding vias V9–V12 and via rules. Widths at half pitch, alternating preferred directions, single-exposure spacing rules on the new coarse layers, ASAP7's LEF58 rules retained on M1–M3.
2. **Track file.** One `make_tracks` line per layer with the new pitches and offsets.
3. **Routing defaults.** Signal window M2–M10, clocks from M4 (now the first 80 nm layer), tile hardening capped at M3 or M4 so the parent keeps the 80 nm layers, parent power on M5/M6.
4. **PDN strategies.** Rails stay on M1/M2. Tile mesh and pins move to the first coarse layer (M4); parent mesh to M5/M6; the macro-connect pair becomes M4–M5. Strap widths and pitch re-derived for the 80 nm layers.
5. **Wire RC estimates.** Scale ASAP7's per-layer resistance and capacitance by the width and thickness ratios (R ∝ 1/(w·t), C roughly constant per length for a fixed aspect ratio). Document them as estimates.
6. **Extraction rules.** OpenRCX rules are per process. Two options: regenerate with OpenRCX's pattern flow against a field-solver run on the new stack, or reuse ASAP7's rules through a layer map and accept a stated inaccuracy. Start with the second, upgrade when a solver run is available.
7. **KLayout layer map** extended to the new layers for GDS merge and viewing.
8. **Validation.** Re-harden the PE and rebuild the 2x2 matrix on the variant; compare per-layer track occupancy, wire length, timing and DRC against the ASAP7 baseline. Check the extracted parasitics against the RC estimates.

Effort: about two days of platform editing plus the validation runs. Result: a routing-faithful proxy of the N+3 stack with ASAP7 cells and devices.

### Phase 2 — DUV-style local routing rules

Goal: approximate the reduced routing flexibility of SAQP/SADP layers. OpenROAD has no switch for strictly unidirectional layers, so model it through capacity: raise the global-routing layer adjustment on M2 and M3 (for example from 0.25 to 0.4–0.5), and increase the minimum pin pitch for block pins on those layers. Calibrate the adjustment so that ASAP7 local-layer occupancy on a reference block matches the N+3 track-density ratio. Cost: hours. Limitation: a statistical proxy, not a rule-accurate model.

### Phase 3 — cell-area proxy

The 5.7-track, single-diffusion-break, two-fin library cannot be produced from ASAP7: it is a cell redesign, and the only public ASAP7 library is the 7.5-track one. Keep the analytical 0.70 factor of section 4, applied per cell class if better data appears (NAND-like cells 0.67; flops unknown). Report both columns in every area table.

### Phase 4 — calibration with HiSilicon data (only under agreement)

If HiSilicon can share a design-rule summary, a metal-stack table with RC, or a TechInsights report, replace the estimates of Phase 1 items 5–6 with measured values. If they can share a SMIC N+3 liberty and LEF under NDA, the flow can switch platforms wholesale: it is technology-agnostic by construction, and the ASAP7 variant becomes unnecessary. Device-model refitting (BSIM-CMG) and liberty re-characterization are out of scope for this flow; they need SPICE models and a characterization tool.

### What each phase buys

| Phase | Area comparability | Routing comparability                | Timing/power comparability    |
| ----- | ------------------ | ------------------------------------ | ----------------------------- |
| 0     | scaled column      | statement of bias                    | statement of bias             |
| 1     | unchanged          | faithful layer roles and capacity    | RC estimated                  |
| 2     | unchanged          | local-layer flexibility approximated | unchanged                     |
| 3     | per-class factors  | unchanged                            | unchanged                     |
| 4     | real               | real                                 | real only with a real library |

## 6. Open gaps

Supply voltage, drive currents and FO4 of N+3 devices; per-layer wire RC and via resistance; the full design-rule set; SRAM compiler data; the material and process-flow analysis (paywalled); independent confirmation of the 113.4 MTr/mm² figure; which Ascend generation moves to N+3 and when.

## 7. Sources

- SemiAnalysis, "Is SMIC N+3's Metal Pitch Smaller than Intel 18A's?" (STEEL Kirin 9030 teardown), June 2026: https://newsletter.semianalysis.com/p/steel-smic-n3-teardown
- TechInsights, "SMIC N+3 Confirmed: Kirin 9030 Analysis": https://www.techinsights.com/blog/smic-n3-confirmed-kirin-9030-analysis-reveals-how-close-smic-5nm
- TechInsights, "HiSilicon Kirin 9030 Pro (SMIC N+3) Process Flow Analysis": https://www.techinsights.com/blog/smic-n3-kirin-9030-pro-process-flow-analysis
- SemiWiki / TechInsights, "Kirin 9030 Hints at SMIC's Possible Paths Toward >300 MTr/mm² Without EUV": https://semiwiki.com/semiconductor-services/techinsights/365118-forwarded-this-email-subscribe-here-for-more-kirin-9030-hints-at-smics-possible-paths-toward-300-mtr-mm2-without-euv/
- Tom's Hardware coverage of the teardown and of the Kirin 9030 node.
- RCR Wireless, Huawei Ascend production and node reports, 2025–2026.
- L. T. Clark et al., "ASAP7: A 7-nm finFET predictive process design kit", Microelectronics Journal, 2016 (PDF and design-rule manual in the local PDK install).
- ASAP7 tech and cell LEF in the local install (pitches, cell footprints).
