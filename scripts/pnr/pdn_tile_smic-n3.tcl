# -----------------------------------------------------------------------------
# Author: Simone Machetti
# SPDX-License-Identifier: Apache-2.0
# -----------------------------------------------------------------------------
#
# pdn_tile.tcl for the smic-n3 metal stack (BEOL=smic-n3): power grid for a block
# hardened as a hard macro under a parent that routes over it. On this stack the
# first coarse layer is M4, so the block is capped one layer lower than on
# ASAP7: rails on M1/M2, vertical M3 straps that tie the rails together, and a
# horizontal M4 mesh exposed as the block power pins. M4 runs parallel to the
# rails and cannot tie them by itself, hence the M3 straps. Nothing is placed on
# M5 or above, so the hardened block obstructs only M1-M4. Pair with
# MAX_ROUTE_LAYER=M4 and PIN_LAYERS_VER=M3 when hardening the block, and with
# pdn_macro_smic-n3.tcl (which drops the parent M5 straps onto these M4 pins)
# in the assembly.
#
# The M3 straps are ASAP7's M5 straps scaled by the pitch ratio 44/48, which
# lands on 0.11, a legal M3 special-route width; the M4 straps are the 80 nm
# strap of the stack's flat strategy, turned horizontal.
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
# Standard cell grid (M1/M2 rails, M3 ties, M4 mesh exposed as the block power pins)
# -----------------------------------------------------------------------------
define_pdn_grid -name {top} -voltage_domains {CORE} -pins {M4}
add_pdn_stripe -grid {top} -layer {M1} -width {0.018} -pitch {0.54} -offset {0} -followpins
add_pdn_stripe -grid {top} -layer {M2} -width {0.018} -pitch {0.54} -offset {0} -followpins
add_pdn_stripe -grid {top} -layer {M3} -width {0.11} -spacing {0.066} -pitch {4.95} -offset {0.275}
add_pdn_stripe -grid {top} -layer {M4} -width {0.2}  -spacing {0.12}  -pitch {9.0}  -offset {0.5}
add_pdn_connect -grid {top} -layers {M1 M2}
add_pdn_connect -grid {top} -layers {M2 M3}
add_pdn_connect -grid {top} -layers {M3 M4}
