#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Author: Simone Machetti
#
# Description:
#   Intra-PE area breakdown for the four PE variants - baseline (pe), square
#   (pe_sqr), BFP (pe_bfp) and square-BFP (pe_sqr_bfp). Complements
#   run_syn_area.sh, which measures whole components: this script opens the PE up
#   and reports how its area splits across the DP8 array, the compression tree and
#   the accumulation array. Pass A synthesizes the two dot-product cores on their
#   own (dp_8, dp_8_sqr) for the DP-level comparison; pass B synthesizes each PE
#   with the boundaries of its tree, its accumulator and its DP core preserved via
#   KEEP_MODULES, so stat -hierarchy reports one Chip area per preserved module.
#   The sections are then DP8 array = 16 x dp_8*, compression tree = pe_array* -
#   16 x dp_8*, accumulation array = acc_array*, PE glue = pe* - pe_array* -
#   acc_array* (operand mask + the two acc pipeline register banks).
#
#   Preserving a boundary blocks cross-boundary optimization, so the hierarchical
#   PE total does NOT match the flat PE area published by run_syn_area.sh - the
#   delta is reported by the extraction below and must be quoted alongside any
#   breakdown taken from these runs.
#
#   Every run uses the default CLK_PERIOD_NS (1.0), matching run_syn_area.sh, so
#   the numbers are comparable with the component areas measured there.
# -----------------------------------------------------------------------------

set -e

cd "$(dirname "$0")/../../.." || exit 1
source sourceme.sh

# -----------------------------------------------------------------------------
# Pass A - standalone dot-product cores
# -----------------------------------------------------------------------------
make syn PROJECT=ai-core TOP_LEVEL=dp_8     OUT_DIR=dp_8_syn
make syn PROJECT=ai-core TOP_LEVEL=dp_8_sqr OUT_DIR=dp_8_sqr_syn

# -----------------------------------------------------------------------------
# Pass B - PEs with the internal module boundaries preserved
# -----------------------------------------------------------------------------
make syn PROJECT=ai-core TOP_LEVEL=pe OUT_DIR=pe_hier_syn \
    KEEP_MODULES="pe_array acc_array dp_8"

make syn PROJECT=ai-core TOP_LEVEL=pe_sqr OUT_DIR=pe_sqr_hier_syn \
    KEEP_MODULES="pe_array_sqr acc_array_sqr dp_8_sqr"

make syn PROJECT=ai-core TOP_LEVEL=pe_bfp OUT_DIR=pe_bfp_hier_syn \
    KEEP_MODULES="pe_array_bfp acc_array_bfp dp_8"

make syn PROJECT=ai-core TOP_LEVEL=pe_sqr_bfp OUT_DIR=pe_sqr_bfp_hier_syn \
    KEEP_MODULES="pe_array_sqr_bfp acc_array_sqr_bfp dp_8_sqr ext_inject_sqr_bfp"

make syn PROJECT=ai-core TOP_LEVEL=dp_8_bpl_a_bfp OUT_DIR=dp_8_bpl_a_bfp_syn
make syn PROJECT=ai-core TOP_LEVEL=dp_8_bpl_b_bfp OUT_DIR=dp_8_bpl_b_bfp_syn

make syn PROJECT=ai-core TOP_LEVEL=pe_bpl_a_bfp OUT_DIR=pe_bpl_a_bfp_hier_syn \
    KEEP_MODULES="pe_array_bpl_a_bfp acc_array_bpl_bfp dp_8_bpl_a_bfp"

make syn PROJECT=ai-core TOP_LEVEL=pe_bpl_b_bfp OUT_DIR=pe_bpl_b_bfp_hier_syn \
    KEEP_MODULES="pe_array_bpl_b_bfp acc_array_bpl_bfp dp_8_bpl_b_bfp"
