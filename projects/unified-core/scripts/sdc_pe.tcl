# -----------------------------------------------------------------------------
# Author: Simone Machetti
# -----------------------------------------------------------------------------
#
# I/O timing budget for hardening the `pe` tile as a hard macro: the share of
# the period the parent may spend before each input pin and after each output
# pin. The classes follow the slack each port class had when the tile was
# hardened with no budget: 20 % on the operand buses and their sign controls,
# 50 % on the accumulator, the carry chain and the registered outputs, 10 % on
# the tap and accumulate selects, none on the enables and the shift select,
# whose paths gate the tree right after the pin. Sourced after the generated
# constraints (SDC=), also from inside the checkpoint loader, so the period is
# read back from the virtual clock.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
proc budget {pct ports} {
    set period [get_property [get_clocks vclk] period]
    set_input_delay [expr {$period * $pct / 100.0}] -clock vclk [get_ports $ports]
}

# -----------------------------------------------------------------------------
# Budgets
# -----------------------------------------------------------------------------
budget 20 {a_dp8_i* b_dp8_i* is_signed_a_i* is_signed_b_i*}
budget 50 {acc_i*}
budget 10 {sel_out_i* sel_acc_i}
budget 50 {prop_carry_i}
budget  0 {en_i en_level_i* sel_shift_i*}

set_output_delay [expr {[get_property [get_clocks vclk] period] * 0.5}] -clock vclk [all_outputs]
