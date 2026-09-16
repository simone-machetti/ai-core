# -----------------------------------------------------------------------------
# Author: Simone Machetti
# -----------------------------------------------------------------------------
#
# Pin plan for hardening the `pe` tile as a hard macro of the top_NxN grid.
# Each bus goes to the edge the grid reaches it from and is ordered by bit
# index: the A bus and the shared control on the top edge, the B bus on the
# left, the accumulator on the bottom, the outputs with clock and reset on the
# right. Sourced by scripts/pnr/1_floorplan.tcl before place_pins (PINS=). Port
# names are the flat vectors of the synthesized netlist.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
proc bus_pins {name width} {
    set pins {}
    for {set i 0} {$i < $width} {incr i} {
        lappend pins "${name}\[$i\]"
    }
    return $pins
}

# -----------------------------------------------------------------------------
# Pin groups
# -----------------------------------------------------------------------------
set ctrl_pins [concat en_i [bus_pins en_level_i 3] [bus_pins is_signed_a_i 16] \
                      [bus_pins is_signed_b_i 16] [bus_pins sel_shift_i 3] \
                      [bus_pins sel_out_i 2] sel_acc_i prop_carry_i]

set_io_pin_constraint -pin_names [bus_pins a_dp8_i 1024] -region top:*    -group -order
set_io_pin_constraint -pin_names $ctrl_pins              -region top:*    -group -order
set_io_pin_constraint -pin_names [bus_pins b_dp8_i 512]  -region left:*   -group -order
set_io_pin_constraint -pin_names [bus_pins acc_i 160]    -region bottom:* -group -order
set_io_pin_constraint -pin_names [bus_pins out_o 160]    -region right:*  -group -order
set_io_pin_constraint -pin_names {clk_i rst_ni}          -region right:*  -group -order
