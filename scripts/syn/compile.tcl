# -----------------------------------------------------------------------------
# Author: Simone Machetti
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Reset the design
# -----------------------------------------------------------------------------
yosys "design -reset"

# -----------------------------------------------------------------------------
# Import Yosys Slang plugin
# -----------------------------------------------------------------------------
yosys "plugin -i $env(YOSYS_SLANG_HOME)/bin/slang.so"

# -----------------------------------------------------------------------------
# Read libraries to Yosys database
# -----------------------------------------------------------------------------
yosys "read_liberty -lib $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_SEQ_RVT_TT_nldm_220123.lib"
yosys "read_liberty -lib $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_SIMPLE_RVT_TT_nldm_211120.lib"
yosys "read_liberty -lib $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_INVBUF_RVT_TT_nldm_220122.lib"
yosys "read_liberty -lib $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_AO_RVT_TT_nldm_211120.lib"
yosys "read_liberty -lib $env(ASAP7_HOME)/lib/NLDM/asap7sc7p5t_OA_RVT_TT_nldm_211120.lib"

# -----------------------------------------------------------------------------
# Read SystemVerilog sources
# -----------------------------------------------------------------------------
set rtl_dir "$env(REPO_HOME)/projects/$env(SEL_PROJECT)/rtl"
set rtl_files [lsort [split [exec find $rtl_dir -name "*.sv"] "\n"]]

set inc_flags ""
foreach dir [lsort [split [exec find $rtl_dir -type d] "\n"]] {
    append inc_flags " -I $dir"
}

set g_flags ""
if {$env(SEL_PARAMS) ne "none"} {
    foreach param [split $env(SEL_PARAMS)] {
        append g_flags " -G $param"
    }
}

set kh_flag ""
if {$env(SEL_KEEP_HIERARCHY) eq "1"} {
    set kh_flag " --keep-hierarchy"
}

yosys "read_slang --single-unit [join $rtl_files]$inc_flags --top $env(SEL_TOP_LEVEL)$g_flags$kh_flag"
