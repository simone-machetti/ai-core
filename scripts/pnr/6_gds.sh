#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# Author: Simone Machetti
# -----------------------------------------------------------------------------

set -euo pipefail

PROJ="${REPO_HOME}/projects/${SEL_PROJECT}"
IMP="${PROJ}/imp/${SEL_OUT_DIR}"

if ! command -v klayout > /dev/null; then
    echo "Error: klayout not found on PATH: cannot merge design.def into design.gds." >&2
    exit 1
fi

TECH_LEF="${ASAP7_HOME}/lef/asap7_tech_1x_201209.lef"
SC_LEF="${ASAP7_HOME}/lef/asap7sc7p5t_28_R_1x_220121a.lef"
SC_GDS="${ASAP7_HOME}/gds/asap7sc7p5t_28_R_220121a.gds"

sed "s,<lef-files>.*</lef-files>,<lef-files>${TECH_LEF}</lef-files><lef-files>${SC_LEF}</lef-files>," \
    "${ASAP7_HOME}/KLayout/asap7.lyt" > "${IMP}/output/klayout.lyt"

klayout -zz \
    -rd design_name="${SEL_TOP_LEVEL}" \
    -rd in_def="${IMP}/output/design.def" \
    -rd in_files="${SC_GDS}" \
    -rd seal_file="" \
    -rd layer_map="" \
    -rd out_file="${IMP}/output/design.gds" \
    -rd tech_file="${IMP}/output/klayout.lyt" \
    -r "${REPO_HOME}/scripts/pnr/def2stream.py"
