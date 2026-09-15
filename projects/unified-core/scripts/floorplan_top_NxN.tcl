# -----------------------------------------------------------------------------
# Author: Simone Machetti
# -----------------------------------------------------------------------------
#
# Macro floorplan for the baseline top_NxN grid. Places the N x N hardened `pe`
# macros as a centered square array in the core, leaving the surrounding ring
# for the shared ctrl, the per-row/col dispatch logic, the clock gates and the
# boundary pins. Sourced by scripts/pnr/1_floorplan.tcl (after the core exists
# and the macros are loaded), then followed by cut_rows.
#
# N, the tile size and the exact instance names are all discovered from the
# design, so the same file serves 2x2, 8x8 and 16x16 unchanged. Row and column
# are parsed from each pe instance name (gen_pe_row[r].gen_pe_col[c].pe_i).
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Knobs
# -----------------------------------------------------------------------------
set CHANNEL_UM $::env(SEL_MACRO_CHANNEL)

# -----------------------------------------------------------------------------
# Database handles
# -----------------------------------------------------------------------------
set block [ord::get_db_block]
set dbu   [expr {double([$block getDbUnitsPerMicron])}]

# -----------------------------------------------------------------------------
# Collect the pe macro instances with their (row, col) parsed from the name
# -----------------------------------------------------------------------------
set tiles  {}
set master ""
foreach inst [$block getInsts] {
    set m [$inst getMaster]
    if {[$m getName] eq "pe"} {
        set name [$inst getName]
        if {![regexp {row\D*(\d+)\D.*col\D*(\d+)} $name -> r c]} {
            error "floorplan_top_NxN: cannot parse row/col from '$name'"
        }
        lappend tiles [list $name $r $c]
        if {$master eq ""} { set master $m }
    }
}
set n_pe [llength $tiles]
if {$n_pe == 0} {
    error "floorplan_top_NxN: no `pe` macros found - is this a MACRO_DIRS run?"
}
set N [expr {int(sqrt($n_pe) + 0.5)}]
if {$N * $N != $n_pe} {
    error "floorplan_top_NxN: $n_pe pe macros is not a perfect square"
}

set tile_w [expr {[$master getWidth]  / $dbu}]
set tile_h [expr {[$master getHeight] / $dbu}]

# -----------------------------------------------------------------------------
# Core box and the centered lower-left origin of the N x N block
# -----------------------------------------------------------------------------
set core    [$block getCoreArea]
set core_x0 [expr {[$core xMin] / $dbu}]
set core_y0 [expr {[$core yMin] / $dbu}]
set core_w  [expr {([$core xMax] - [$core xMin]) / $dbu}]
set core_h  [expr {([$core yMax] - [$core yMin]) / $dbu}]

set span_w [expr {$N * $tile_w + ($N - 1) * $CHANNEL_UM}]
set span_h [expr {$N * $tile_h + ($N - 1) * $CHANNEL_UM}]
set org_x  [expr {$core_x0 + ($core_w - $span_w) / 2.0}]
set org_y  [expr {$core_y0 + ($core_h - $span_h) / 2.0}]

if {$org_x < $core_x0 || $org_y < $core_y0} {
    error "floorplan_top_NxN: the ${N}x${N} macro block does not fit in the core - lower CORE_UTIL"
}

# -----------------------------------------------------------------------------
# Place every tile (row r from bottom, column c from left) by its real name
# -----------------------------------------------------------------------------
foreach t $tiles {
    lassign $t name r c
    set x [expr {$org_x + $c * ($tile_w + $CHANNEL_UM)}]
    set y [expr {$org_y + $r * ($tile_h + $CHANNEL_UM)}]
    place_macro -macro_name $name -location [list $x $y] -orientation R0
}
