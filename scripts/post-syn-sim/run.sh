#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# Author: Simone Machetti
# -----------------------------------------------------------------------------

set -euo pipefail

g_flags=()
if [ "${SEL_PARAMS}" != "none" ]; then
    for param in ${SEL_PARAMS}; do
        g_flags+=("-G${param}")
    done
fi

verilator \
    -sv \
    --binary \
    --timing \
    --trace \
    --trace-underscore \
    --trace-max-array 0 \
    --trace-max-width 0 \
    -Wall \
    -Wno-fatal \
    -Wno-SPECIFYIGN \
    -Wno-DECLFILENAME \
    -Wno-UNUSEDSIGNAL \
    -DPOST_SYN_SIM \
    -DVCD \
    -DCLK_PERIOD_NS="${SEL_CLK_PERIOD_NS}" \
    "${g_flags[@]}" \
    --top-module "tb_${SEL_TOP_LEVEL}" \
    -DPOST_SYNTH=1 \
    --x-initial fast \
    --x-assign fast \
    -f "${CODE_HOME}/ai-core/scripts/post-syn-sim/filelist.f" \
       "${CODE_HOME}/ai-core/projects/${SEL_PROJECT}/tb/tb_${SEL_TOP_LEVEL}.sv" \
    -Mdir "${CODE_HOME}/ai-core/projects/${SEL_PROJECT}/sim/${SEL_OUT_DIR}/build/obj_dir" \
    -o "${CODE_HOME}/ai-core/projects/${SEL_PROJECT}/sim/${SEL_OUT_DIR}/build/simv" \
    | tee "${CODE_HOME}/ai-core/projects/${SEL_PROJECT}/sim/${SEL_OUT_DIR}/output/compile.log"

exec "${CODE_HOME}/ai-core/projects/${SEL_PROJECT}/sim/${SEL_OUT_DIR}/build/simv" "$@" \
    | tee "${CODE_HOME}/ai-core/projects/${SEL_PROJECT}/sim/${SEL_OUT_DIR}/output/run.log"
