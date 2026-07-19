#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Author: Simone Machetti
#
# Description:
#   Per-module area synthesis runs for the baseline (top_NxN) vs square
#   (top_NxN_sqr) 8x8 comparison. Each command synthesizes one component with the
#   shared Yosys + ASAP7 flow and writes its hierarchical cell-area report to
#   projects/ai-core/imp/<module>/report/area.rpt. The 8x8 areas are assembled
#   analytically from these per-module areas (component list and instance counts
#   in run_syn_area.md). Commands are appended below as they are run, so the whole
#   sweep stays rerunnable.
# -----------------------------------------------------------------------------

cd "$(dirname "$0")/../../.." || exit 1
source sourceme.sh

make syn PROJECT=ai-core TOP_LEVEL=ctrl OUT_DIR=ctrl
make syn PROJECT=ai-core TOP_LEVEL=disp_array_a OUT_DIR=disp_array_a
make syn PROJECT=ai-core TOP_LEVEL=disp_array_b OUT_DIR=disp_array_b
make syn PROJECT=ai-core TOP_LEVEL=pe OUT_DIR=pe

make syn PROJECT=ai-core TOP_LEVEL=ctrl_sqr OUT_DIR=ctrl_sqr
make syn PROJECT=ai-core TOP_LEVEL=const_sqr OUT_DIR=const_sqr
make syn PROJECT=ai-core TOP_LEVEL=disp_array_a_sqr OUT_DIR=disp_array_a_sqr
make syn PROJECT=ai-core TOP_LEVEL=disp_array_b_sqr OUT_DIR=disp_array_b_sqr
make syn PROJECT=ai-core TOP_LEVEL=pe_array_alpha_sqr OUT_DIR=pe_array_alpha_sqr
make syn PROJECT=ai-core TOP_LEVEL=pe_array_beta_sqr OUT_DIR=pe_array_beta_sqr
make syn PROJECT=ai-core TOP_LEVEL=pe_sqr OUT_DIR=pe_sqr
