#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Author: Simone Machetti
#
# Description:
#   Area synthesis runs for the four PE-grid variants - baseline (top_NxN),
#   square (top_NxN_sqr), BFP (top_NxN_bfp) and square-BFP (top_NxN_sqr_bfp).
#   Every run is at 2x2 only: pass A synthesizes each component once on its own
#   (netlist -> projects/ai-core/imp/<module>/output/netlist.v, area ->
#   report/area.rpt), pass B synthesizes the 2x2 grids linking those netlists via
#   BLACKBOX_MODULES. The 8x8 and 16x16 figures are then assembled ANALYTICALLY
#   from the per-component areas and a per-N count model (PE = N^2, dispatch /
#   alpha-beta = N, icg = 2N+N^2, ctrl/const/glue = 1) in doc/charts/hist_syn_area.py,
#   so no full 8x8/16x16 grid is ever synthesized (the old method needed ~26 GB
#   for 16x16). The 2x2 grid area gives the fixed "glue" term. Method, component
#   list and results in the wiki experiment page wiki/experiments/syn_area.md.
# -----------------------------------------------------------------------------

cd "$(dirname "$0")/../../.." || exit 1
source sourceme.sh

BB_BAS="pe ctrl disp_array_a disp_array_b icg"

BB_SQR="pe_sqr ctrl_sqr const_sqr disp_array_a_sqr disp_array_b_sqr \
        pe_array_alpha_sqr pe_array_beta_sqr icg"

BB_BFP="pe_bfp ctrl disp_array_a disp_array_exp_a_bfp disp_array_b \
        disp_array_exp_b_bfp icg"

BB_SQR_BFP="pe_sqr_bfp ctrl_sqr const_sqr_bfp disp_array_a_sqr \
            disp_array_exp_a_sqr_bfp disp_array_b_sqr disp_array_exp_b_sqr_bfp \
            pe_array_alpha_sqr_bfp pe_array_beta_sqr_bfp icg"

# -----------------------------------------------------------------------------
# Pass A - per-module runs
# -----------------------------------------------------------------------------
make syn PROJECT=ai-core TOP_LEVEL=icg OUT_DIR=icg_syn

# baseline
make syn PROJECT=ai-core TOP_LEVEL=ctrl OUT_DIR=ctrl_syn
make syn PROJECT=ai-core TOP_LEVEL=disp_array_a OUT_DIR=disp_array_a_syn
make syn PROJECT=ai-core TOP_LEVEL=disp_array_b OUT_DIR=disp_array_b_syn
make syn PROJECT=ai-core TOP_LEVEL=pe OUT_DIR=pe_syn

# square
make syn PROJECT=ai-core TOP_LEVEL=ctrl_sqr OUT_DIR=ctrl_sqr_syn
make syn PROJECT=ai-core TOP_LEVEL=const_sqr OUT_DIR=const_sqr_syn
make syn PROJECT=ai-core TOP_LEVEL=disp_array_a_sqr OUT_DIR=disp_array_a_sqr_syn
make syn PROJECT=ai-core TOP_LEVEL=disp_array_b_sqr OUT_DIR=disp_array_b_sqr_syn
make syn PROJECT=ai-core TOP_LEVEL=pe_array_alpha_sqr OUT_DIR=pe_array_alpha_sqr_syn
make syn PROJECT=ai-core TOP_LEVEL=pe_array_beta_sqr OUT_DIR=pe_array_beta_sqr_syn
make syn PROJECT=ai-core TOP_LEVEL=pe_sqr OUT_DIR=pe_sqr_syn

# BFP
make syn PROJECT=ai-core TOP_LEVEL=disp_array_exp_a_bfp OUT_DIR=disp_array_exp_a_bfp_syn
make syn PROJECT=ai-core TOP_LEVEL=disp_array_exp_b_bfp OUT_DIR=disp_array_exp_b_bfp_syn
make syn PROJECT=ai-core TOP_LEVEL=pe_bfp OUT_DIR=pe_bfp_syn

# square BFP
make syn PROJECT=ai-core TOP_LEVEL=disp_array_exp_a_sqr_bfp OUT_DIR=disp_array_exp_a_sqr_bfp_syn
make syn PROJECT=ai-core TOP_LEVEL=disp_array_exp_b_sqr_bfp OUT_DIR=disp_array_exp_b_sqr_bfp_syn
make syn PROJECT=ai-core TOP_LEVEL=pe_array_alpha_sqr_bfp OUT_DIR=pe_array_alpha_sqr_bfp_syn
make syn PROJECT=ai-core TOP_LEVEL=pe_array_beta_sqr_bfp OUT_DIR=pe_array_beta_sqr_bfp_syn
make syn PROJECT=ai-core TOP_LEVEL=const_sqr_bfp OUT_DIR=const_sqr_bfp_syn
make syn PROJECT=ai-core TOP_LEVEL=pe_sqr_bfp OUT_DIR=pe_sqr_bfp_syn

# -----------------------------------------------------------------------------
# Pass B - 2x2 grids (blackboxed)
# -----------------------------------------------------------------------------
make syn PROJECT=ai-core TOP_LEVEL=top_NxN OUT_DIR=top_2x2_syn PARAMS="N=2" \
    BLACKBOX_MODULES="$BB_BAS"

make syn PROJECT=ai-core TOP_LEVEL=top_NxN_sqr OUT_DIR=top_2x2_sqr_syn PARAMS="N=2" \
    BLACKBOX_MODULES="$BB_SQR"

make syn PROJECT=ai-core TOP_LEVEL=top_NxN_bfp OUT_DIR=top_2x2_bfp_syn PARAMS="N=2" \
    BLACKBOX_MODULES="$BB_BFP"

make syn PROJECT=ai-core TOP_LEVEL=top_NxN_sqr_bfp OUT_DIR=top_2x2_sqr_bfp_syn PARAMS="N=2" \
    BLACKBOX_MODULES="$BB_SQR_BFP"
