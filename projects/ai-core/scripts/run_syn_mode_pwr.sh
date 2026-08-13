#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Author: Simone Machetti
#
# Description:
#   Per-mode dynamic power runs for the five PE-grid variants - baseline
#   (top_NxN), square (top_NxN_sqr), BFP (top_NxN_bfp) and square-BFP
#   (top_NxN_sqr_bfp) - measured on the complete 2x2 grids. Same four
#   passes as run_syn_pwr.sh, but pass C runs each of the 11 modes on its own
#   with NUM_VEC vectors so every mode gets its own activity.vcd and its own
#   power report, instead of one VCD averaged over all modes. The 8x8 and 16x16
#   per-mode figures are then assembled from the per-component unit powers, since
#   gate-level simulation of those grids does not fit in memory. Method and
#   results in the wiki experiment page wiki/experiments/syn_mode_pwr.md.
#
#   MODE_SEL and NUM_STREAM are read from +mode / +vectors at run time, so the
#   whole sweep reuses ONE compiled binary per variant. That matters: the
#   Verilator build takes ~10 min and the simulation itself takes ~2 s, so
#   rebuilding per mode would turn a 35 min sweep into a 4 h one.
#
#   Each activity.vcd is deleted once its power report exists - 22 of them would
#   otherwise be ~3 GB, and any one is regenerated in seconds from the binary.
# -----------------------------------------------------------------------------

cd "$(dirname "$0")/../../.." || exit 1
source sourceme.sh

set -e

PROJ="$REPO_HOME/projects/ai-core"

MODES="1 2 3 5 6 7 8 9 10 11 12"
NUM_VEC=100
CLK=10

BB_BAS="pe ctrl disp_array_a disp_array_b icg"

BB_SQR="pe_sqr ctrl_sqr const_sqr disp_array_a_sqr disp_array_b_sqr \
        pe_array_alpha_sqr pe_array_beta_sqr icg"

BB_BFP="pe_bfp ctrl disp_array_a disp_array_exp_a_bfp disp_array_b \
        disp_array_exp_b_bfp icg"

BB_SQR_BFP="pe_sqr_bfp ctrl_sqr const_sqr_bfp disp_array_a_sqr \
            disp_array_exp_a_sqr_bfp disp_array_b_sqr disp_array_exp_b_sqr_bfp \
            pe_array_alpha_sqr_bfp pe_array_beta_sqr_bfp icg"

BB_BPL_B_BFP="pe_bpl_b_bfp ctrl disp_array_a_bpl_b_bfp disp_array_exp_a_bfp disp_array_b \
              disp_array_exp_b_bfp icg"

BB_BPL_A_BFP="pe_bpl_a_bfp ctrl disp_array_a disp_array_exp_a_bfp disp_array_b_bpl_a_bfp \
            disp_array_exp_b_bfp icg"

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

# bit-plane-A BFP
make syn PROJECT=ai-core TOP_LEVEL=disp_array_b_bpl_a_bfp OUT_DIR=disp_array_b_bpl_a_bfp_syn
make syn PROJECT=ai-core TOP_LEVEL=pe_bpl_a_bfp OUT_DIR=pe_bpl_a_bfp_syn
make syn PROJECT=ai-core TOP_LEVEL=disp_array_a_bpl_b_bfp OUT_DIR=disp_array_a_bpl_b_bfp_syn
make syn PROJECT=ai-core TOP_LEVEL=pe_bpl_b_bfp OUT_DIR=pe_bpl_b_bfp_syn

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

make syn PROJECT=ai-core TOP_LEVEL=top_NxN_bpl_a_bfp OUT_DIR=top_2x2_bpl_a_bfp_syn PARAMS="N=2" \
    BLACKBOX_MODULES="$BB_BPL_A_BFP"

make syn PROJECT=ai-core TOP_LEVEL=top_NxN_bpl_b_bfp OUT_DIR=top_2x2_bpl_b_bfp_syn PARAMS="N=2" \
    BLACKBOX_MODULES="$BB_BPL_B_BFP"

# -----------------------------------------------------------------------------
# Passes C and D - one gate-level simulation and one power run per mode
# -----------------------------------------------------------------------------
sweep () {
    local top=$1 tb=$2 grid=$3 bb=$4

    local netlist="${grid}_syn"
    local sim_dir="${grid}_post_syn_sim"

    make post-syn-sim PROJECT=ai-core TOP_LEVEL="$top" OUT_DIR="$sim_dir" \
        NETLIST_DIR="$netlist" TB="$tb" CLK_PERIOD_NS=$CLK VCD=1
    rm -f "$PROJ/sim/$sim_dir/output/activity.vcd"

    local simv="$PROJ/sim/$sim_dir/build/simv"

    for m in $MODES; do
        local vcd_dir="${grid}_m${m}_post_syn_sim"
        mkdir -p "$PROJ/sim/$vcd_dir/output"
        ( cd "$PROJ/sim/$vcd_dir/output" && "$simv" +mode=$m +vectors=$NUM_VEC )

        sed -i -E '/^\$var real /d; /^r[0-9.]/d' "$PROJ/sim/$vcd_dir/output/activity.vcd"

        make post-syn-dpa PROJECT=ai-core TOP_LEVEL="$top" OUT_DIR="${grid}_m${m}_post_syn_dpa" \
            NETLIST_DIR="$netlist" VCD_DIR="$vcd_dir" TB="$tb" CLK_PERIOD_NS=$CLK \
            BLACKBOX_MODULES="$bb"

        rm -f "$PROJ/sim/$vcd_dir/output/activity.vcd"
    done
}

sweep top_NxN           tb_top_NxN_pwr           top_2x2           "$BB_BAS"
sweep top_NxN_sqr       tb_top_NxN_sqr_pwr       top_2x2_sqr       "$BB_SQR"
sweep top_NxN_bfp       tb_top_NxN_bfp_pwr       top_2x2_bfp       "$BB_BFP"
sweep top_NxN_sqr_bfp   tb_top_NxN_sqr_bfp_pwr   top_2x2_sqr_bfp   "$BB_SQR_BFP"
sweep top_NxN_bpl_a_bfp tb_top_NxN_bpl_a_bfp_pwr top_2x2_bpl_a_bfp "$BB_BPL_A_BFP"
sweep top_NxN_bpl_b_bfp tb_top_NxN_bpl_b_bfp_pwr top_2x2_bpl_b_bfp "$BB_BPL_B_BFP"
