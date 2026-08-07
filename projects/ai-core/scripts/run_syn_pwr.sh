#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Author: Simone Machetti
#
# Description:
#   Dynamic power runs for the four PE-grid variants - baseline (top_NxN), square
#   (top_NxN_sqr), BFP (top_NxN_bfp) and square-BFP (top_NxN_sqr_bfp) - measured
#   on the complete 2x2 grids. Pass A synthesizes every component once on its own,
#   pass B synthesizes the 2x2 grids linking those netlists, pass C runs
#   gate-level simulation with the per-variant power stimulus benches to dump
#   activity.vcd, and pass D annotates that activity onto the netlist in OpenSTA
#   and reports per-instance power. The 8x8 and 16x16 figures are then assembled
#   ANALYTICALLY from the per-component unit powers (per-N count model in
#   doc/charts/hist_syn_pwr.py) - gate-level simulation of those grids does not fit
#   in memory. Pass C re-runs the compiled binary with +vectors=NUM_VEC so the
#   stimulus length matches run_syn_mode_pwr.sh. Method and results in the wiki
#   experiment page wiki/experiments/syn_pwr.md.
#
#   Passes A and B duplicate run_syn_area.sh at N=2 - if that script has already
#   run, only passes C and D (the gate-level sim + power) are actually needed.
# -----------------------------------------------------------------------------

cd "$(dirname "$0")/../../.." || exit 1
source sourceme.sh

PROJ="$REPO_HOME/projects/ai-core"

BB_BAS="pe ctrl disp_array_a disp_array_b icg"

BB_SQR="pe_sqr ctrl_sqr const_sqr disp_array_a_sqr disp_array_b_sqr \
        pe_array_alpha_sqr pe_array_beta_sqr icg"

BB_BFP="pe_bfp ctrl disp_array_a disp_array_exp_a_bfp disp_array_b \
        disp_array_exp_b_bfp icg"

BB_SQR_BFP="pe_sqr_bfp ctrl_sqr const_sqr_bfp disp_array_a_sqr \
            disp_array_exp_a_sqr_bfp disp_array_b_sqr disp_array_exp_b_sqr_bfp \
            pe_array_alpha_sqr_bfp pe_array_beta_sqr_bfp icg"

BB_BPL_BFP="pe_bpl_bfp ctrl disp_array_a disp_array_exp_a_bfp disp_array_b_bpl_bfp \
            disp_array_exp_b_bfp icg"

CLK=10
NUM_VEC=100

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

# bit-plane BFP
make syn PROJECT=ai-core TOP_LEVEL=disp_array_b_bpl_bfp OUT_DIR=disp_array_b_bpl_bfp_syn
make syn PROJECT=ai-core TOP_LEVEL=pe_bpl_bfp OUT_DIR=pe_bpl_bfp_syn

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

make syn PROJECT=ai-core TOP_LEVEL=top_NxN_bpl_bfp OUT_DIR=top_2x2_bpl_bfp_syn PARAMS="N=2" \
    BLACKBOX_MODULES="$BB_BPL_BFP"

# -----------------------------------------------------------------------------
# Pass C - gate-level simulation, dumps activity.vcd
# -----------------------------------------------------------------------------
make post-syn-sim PROJECT=ai-core TOP_LEVEL=top_NxN OUT_DIR=top_2x2_post_syn_sim \
    NETLIST_DIR=top_2x2_syn TB=tb_top_NxN_pwr CLK_PERIOD_NS=$CLK VCD=1
( cd "$PROJ/sim/top_2x2_post_syn_sim/output" && "$PROJ/sim/top_2x2_post_syn_sim/build/simv" +vectors=$NUM_VEC )
sed -i -E '/^\$var real /d; /^r[0-9.]/d' "$PROJ/sim/top_2x2_post_syn_sim/output/activity.vcd"

make post-syn-sim PROJECT=ai-core TOP_LEVEL=top_NxN_sqr OUT_DIR=top_2x2_sqr_post_syn_sim \
    NETLIST_DIR=top_2x2_sqr_syn TB=tb_top_NxN_sqr_pwr CLK_PERIOD_NS=$CLK VCD=1
( cd "$PROJ/sim/top_2x2_sqr_post_syn_sim/output" && "$PROJ/sim/top_2x2_sqr_post_syn_sim/build/simv" +vectors=$NUM_VEC )
sed -i -E '/^\$var real /d; /^r[0-9.]/d' "$PROJ/sim/top_2x2_sqr_post_syn_sim/output/activity.vcd"

make post-syn-sim PROJECT=ai-core TOP_LEVEL=top_NxN_bfp OUT_DIR=top_2x2_bfp_post_syn_sim \
    NETLIST_DIR=top_2x2_bfp_syn TB=tb_top_NxN_bfp_pwr CLK_PERIOD_NS=$CLK VCD=1
( cd "$PROJ/sim/top_2x2_bfp_post_syn_sim/output" && "$PROJ/sim/top_2x2_bfp_post_syn_sim/build/simv" +vectors=$NUM_VEC )
sed -i -E '/^\$var real /d; /^r[0-9.]/d' "$PROJ/sim/top_2x2_bfp_post_syn_sim/output/activity.vcd"

make post-syn-sim PROJECT=ai-core TOP_LEVEL=top_NxN_sqr_bfp OUT_DIR=top_2x2_sqr_bfp_post_syn_sim \
    NETLIST_DIR=top_2x2_sqr_bfp_syn TB=tb_top_NxN_sqr_bfp_pwr CLK_PERIOD_NS=$CLK VCD=1
( cd "$PROJ/sim/top_2x2_sqr_bfp_post_syn_sim/output" && "$PROJ/sim/top_2x2_sqr_bfp_post_syn_sim/build/simv" +vectors=$NUM_VEC )
sed -i -E '/^\$var real /d; /^r[0-9.]/d' "$PROJ/sim/top_2x2_sqr_bfp_post_syn_sim/output/activity.vcd"

make post-syn-sim PROJECT=ai-core TOP_LEVEL=top_NxN_bpl_bfp OUT_DIR=top_2x2_bpl_bfp_post_syn_sim \
    NETLIST_DIR=top_2x2_bpl_bfp_syn TB=tb_top_NxN_bpl_bfp_pwr CLK_PERIOD_NS=$CLK VCD=1
( cd "$PROJ/sim/top_2x2_bpl_bfp_post_syn_sim/output" && "$PROJ/sim/top_2x2_bpl_bfp_post_syn_sim/build/simv" +vectors=$NUM_VEC )
sed -i -E '/^\$var real /d; /^r[0-9.]/d' "$PROJ/sim/top_2x2_bpl_bfp_post_syn_sim/output/activity.vcd"

# -----------------------------------------------------------------------------
# Pass D - VCD-annotated power analysis
# -----------------------------------------------------------------------------
make post-syn-dpa PROJECT=ai-core TOP_LEVEL=top_NxN OUT_DIR=top_2x2_post_syn_dpa \
    NETLIST_DIR=top_2x2_syn VCD_DIR=top_2x2_post_syn_sim TB=tb_top_NxN_pwr CLK_PERIOD_NS=$CLK \
    BLACKBOX_MODULES="$BB_BAS"

make post-syn-dpa PROJECT=ai-core TOP_LEVEL=top_NxN_sqr OUT_DIR=top_2x2_sqr_post_syn_dpa \
    NETLIST_DIR=top_2x2_sqr_syn VCD_DIR=top_2x2_sqr_post_syn_sim TB=tb_top_NxN_sqr_pwr CLK_PERIOD_NS=$CLK \
    BLACKBOX_MODULES="$BB_SQR"

make post-syn-dpa PROJECT=ai-core TOP_LEVEL=top_NxN_bfp OUT_DIR=top_2x2_bfp_post_syn_dpa \
    NETLIST_DIR=top_2x2_bfp_syn VCD_DIR=top_2x2_bfp_post_syn_sim TB=tb_top_NxN_bfp_pwr CLK_PERIOD_NS=$CLK \
    BLACKBOX_MODULES="$BB_BFP"

make post-syn-dpa PROJECT=ai-core TOP_LEVEL=top_NxN_sqr_bfp OUT_DIR=top_2x2_sqr_bfp_post_syn_dpa \
    NETLIST_DIR=top_2x2_sqr_bfp_syn VCD_DIR=top_2x2_sqr_bfp_post_syn_sim TB=tb_top_NxN_sqr_bfp_pwr CLK_PERIOD_NS=$CLK \
    BLACKBOX_MODULES="$BB_SQR_BFP"

make post-syn-dpa PROJECT=ai-core TOP_LEVEL=top_NxN_bpl_bfp OUT_DIR=top_2x2_bpl_bfp_post_syn_dpa \
    NETLIST_DIR=top_2x2_bpl_bfp_syn VCD_DIR=top_2x2_bpl_bfp_post_syn_sim TB=tb_top_NxN_bpl_bfp_pwr CLK_PERIOD_NS=$CLK \
    BLACKBOX_MODULES="$BB_BPL_BFP"
