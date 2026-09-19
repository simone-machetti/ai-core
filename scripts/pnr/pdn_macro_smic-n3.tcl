# -----------------------------------------------------------------------------
# Author: Simone Machetti
# SPDX-License-Identifier: Apache-2.0
# -----------------------------------------------------------------------------
#
# pdn_macro.tcl for the smic-n3 metal stack (BEOL=smic-n3). Blocks hardened on
# this stack are routed up to M4 (see MAX_ROUTE_LAYER + pdn_tile_smic-n3.tcl)
# and expose their horizontal M4 straps as power pins. The standard-cell grid
# runs M1/M2 rails, a vertical M5 mesh and a horizontal M6 mesh; M5 is free over
# the macros, so its straps run across them and drop onto each macro's M4 power
# pins. M7 and above carry no power and are left entirely to routing. Strap
# geometry is that of the stack's flat strategy.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Global connections
# -----------------------------------------------------------------------------
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {^VDD$} -power
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {^VDDPE$}
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {^VDDCE$}
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {^VSS$} -ground
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {^VSSE$}
global_connect

# -----------------------------------------------------------------------------
# Voltage domains
# -----------------------------------------------------------------------------
set_voltage_domain -name {CORE} -power {VDD} -ground {VSS}

# -----------------------------------------------------------------------------
# Standard cell grid (M1/M2 rails, M5 mesh over the whole core, M6 top mesh)
# -----------------------------------------------------------------------------
define_pdn_grid -name {top} -voltage_domains {CORE} -pins {M6}
add_pdn_stripe -grid {top} -layer {M1} -width {0.018} -pitch {0.54} -offset {0} -followpins
add_pdn_stripe -grid {top} -layer {M2} -width {0.018} -pitch {0.54} -offset {0} -followpins
add_pdn_stripe -grid {top} -layer {M5} -width {0.2}  -spacing {0.12} -pitch {9.0}  -offset {0.5}
add_pdn_stripe -grid {top} -layer {M6} -width {0.36} -spacing {0.12} -pitch {6.75} -offset {0.641}
add_pdn_connect -grid {top} -layers {M1 M2}
add_pdn_connect -grid {top} -layers {M2 M5}
add_pdn_connect -grid {top} -layers {M5 M6}

# -----------------------------------------------------------------------------
# Macro grid (drop the parent M5 straps onto each macro's M4 power pins)
# -----------------------------------------------------------------------------
define_pdn_grid -name {MacroGrid} -voltage_domains {CORE} -macro -default -halo {2.0 2.0 2.0 2.0}
add_pdn_connect -grid {MacroGrid} -layers {M4 M5}
