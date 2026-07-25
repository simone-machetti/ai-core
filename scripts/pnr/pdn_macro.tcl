# -----------------------------------------------------------------------------
# Author: Simone Machetti
# -----------------------------------------------------------------------------
#
# Macro-aware PDN. Blocks hardened by this flow are routed up to M6 (M7 left
# free, see MAX_ROUTE_LAYER) and expose their power straps as M6 pins. The
# standard-cell grid runs M1/M2 rails + an M5/M6 mesh in the loose-logic areas;
# an M7 mesh runs over the whole core - including the macros, since M7 is free -
# and drops onto each macro's M6 power pins.
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
# Standard cell grid (M1/M2 rails, M5/M6 mesh, M7 top mesh)
# -----------------------------------------------------------------------------
define_pdn_grid -name {top} -voltage_domains {CORE} -pins {M7}
add_pdn_stripe -grid {top} -layer {M1} -width {0.018} -pitch {0.54} -offset {0} -followpins
add_pdn_stripe -grid {top} -layer {M2} -width {0.018} -pitch {0.54} -offset {0} -followpins
add_pdn_stripe -grid {top} -layer {M5} -width {0.12}  -spacing {0.072} -pitch {5.4} -offset {0.300}
add_pdn_stripe -grid {top} -layer {M6} -width {0.288} -spacing {0.096} -pitch {5.4} -offset {0.513}
add_pdn_stripe -grid {top} -layer {M7} -width {0.288} -spacing {0.096} -pitch {5.4} -offset {0.300}
add_pdn_connect -grid {top} -layers {M1 M2}
add_pdn_connect -grid {top} -layers {M2 M5}
add_pdn_connect -grid {top} -layers {M5 M6}
add_pdn_connect -grid {top} -layers {M6 M7}

# -----------------------------------------------------------------------------
# Macro grid (drop the parent M7 straps onto each macro's M6 power pins)
# -----------------------------------------------------------------------------
define_pdn_grid -name {MacroGrid} -voltage_domains {CORE} -macro -default -halo {2.0 2.0 2.0 2.0}
add_pdn_connect -grid {MacroGrid} -layers {M6 M7}
