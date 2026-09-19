# -----------------------------------------------------------------------------
# Author: Simone Machetti
# SPDX-License-Identifier: Apache-2.0
# -----------------------------------------------------------------------------
#
# Boundary pin plan for the top_NxN grid assembled from hardened `pe` macros.
# It follows the tile's own pin plan: the row A buses enter on the left at the
# height of their row, the column B buses on the top over the span of their
# column, the accumulators on the bottom per column, the outputs leave on the
# right per row, and the grid control sits in the top-left corner. Every bus is
# ordered by bit index. Sourced by scripts/pnr/1_floorplan.tcl after the
# floorplan file placed the tiles, so the spans are read from the placed macros
# and N is discovered from them.
#
# The pin placer keeps an ordered group only up to its section size of 200
# slots, so every bus is split into ordered sub-groups of at most GROUP_MAX pins,
# each confined to its own slice of the row or column span. Synthesis flattens
# the unpacked ports with element 0 at the top of the vector: element k of E
# elements of width W is bits [W*(E-1-k) +: W], and the acc_i/out_q_o element
# index is r*N + c.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Knobs
# -----------------------------------------------------------------------------
set GROUP_MAX 160
set A_W       256
set ACC_W     160

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
proc slice {name W E k} {
    set base [expr {$W * ($E - 1 - $k)}]
    set pins {}
    for {set i 0} {$i < $W} {incr i} {
        lappend pins "${name}\[[expr {$base + $i}]\]"
    }
    return $pins
}

proc place_bus {edge pins lo hi gap dlo dhi} {
    global GROUP_MAX
    set a [expr {max($dlo + 1.0, $lo - $gap)}]
    set b [expr {min($dhi - 1.0, $hi + $gap)}]
    set n [llength $pins]
    set parts [expr {int(ceil(double($n) / $GROUP_MAX))}]
    set per   [expr {int(ceil(double($n) / $parts))}]
    set step  [expr {($b - $a) / $parts}]
    for {set p 0} {$p < $parts} {incr p} {
        set sub [lrange $pins [expr {$p * $per}] [expr {($p + 1) * $per - 1}]]
        if {[llength $sub] == 0} { continue }
        set s0 [expr {$a + $p * $step}]
        set s1 [expr {$a + ($p + 1) * $step}]
        set_io_pin_constraint -pin_names $sub \
            -region ${edge}:[format "%.3f-%.3f" $s0 $s1] -group -order
    }
}

# -----------------------------------------------------------------------------
# Tile spans from the placed macros
# -----------------------------------------------------------------------------
set block [ord::get_db_block]
set dbu   [expr {double([$block getDbUnitsPerMicron])}]
set die   [$block getDieArea]
set die_x0 [expr {[$die xMin] / $dbu}]
set die_y0 [expr {[$die yMin] / $dbu}]
set die_x1 [expr {[$die xMax] / $dbu}]
set die_y1 [expr {[$die yMax] / $dbu}]

array set row_lo {}
array set row_hi {}
array set col_lo {}
array set col_hi {}
foreach inst [$block getInsts] {
    if {[[$inst getMaster] getName] ne "pe"} { continue }
    if {![regexp {row\D*(\d+)\D.*col\D*(\d+)} [$inst getName] -> r c]} {
        error "pins_top_NxN: cannot parse row/col from '[$inst getName]'"
    }
    set bb [$inst getBBox]
    set x0 [expr {[$bb xMin] / $dbu}]
    set x1 [expr {[$bb xMax] / $dbu}]
    set y0 [expr {[$bb yMin] / $dbu}]
    set y1 [expr {[$bb yMax] / $dbu}]
    if {![info exists row_lo($r)] || $y0 < $row_lo($r)} { set row_lo($r) $y0 }
    if {![info exists row_hi($r)] || $y1 > $row_hi($r)} { set row_hi($r) $y1 }
    if {![info exists col_lo($c)] || $x0 < $col_lo($c)} { set col_lo($c) $x0 }
    if {![info exists col_hi($c)] || $x1 > $col_hi($c)} { set col_hi($c) $x1 }
}
set N [array size row_lo]
if {$N == 0} { error "pins_top_NxN: no `pe` macros found - is this a MACRO_DIRS run?" }

set gap_y [expr {$N > 1 ? ($row_lo(1) - $row_hi(0)) / 2.0 : 20.0}]
set gap_x [expr {$N > 1 ? ($col_lo(1) - $col_hi(0)) / 2.0 : 20.0}]

puts [format "pins_top_NxN: die %.1f x %.1f um, %dx%d tiles, half gaps x %.1f y %.1f um" \
    [expr {$die_x1 - $die_x0}] [expr {$die_y1 - $die_y0}] $N $N $gap_x $gap_y]
for {set r 0} {$r < $N} {incr r} {
    puts [format "pins_top_NxN: row %d y %.1f-%.1f   col %d x %.1f-%.1f" \
        $r $row_lo($r) $row_hi($r) $r $col_lo($r) $col_hi($r)]
}

# -----------------------------------------------------------------------------
# Left edge: row A buses
# -----------------------------------------------------------------------------
for {set r 0} {$r < $N} {incr r} {
    set pins [concat [slice in_a_i $A_W $N $r] "en_row_i\[[expr {$N - 1 - $r}]\]"]
    place_bus left $pins $row_lo($r) $row_hi($r) $gap_y $die_y0 $die_y1
}

# -----------------------------------------------------------------------------
# Top edge: grid control, then column B buses
# -----------------------------------------------------------------------------
set ctrl {clk_i rst_ni mode_i[0] mode_i[1] mode_i[2] mode_i[3] sel_acc_i}
set ctrl_hi [expr {max($col_lo(0) - $gap_x, $die_x0 + 6.0)}]
set_io_pin_constraint -pin_names $ctrl \
    -region top:[format "%.3f-%.3f" [expr {$die_x0 + 1.0}] $ctrl_hi] -group -order

for {set c 0} {$c < $N} {incr c} {
    set pins [concat [slice in_b_i $A_W $N $c] "en_col_i\[[expr {$N - 1 - $c}]\]"]
    place_bus top $pins $col_lo($c) $col_hi($c) $gap_x $die_x0 $die_x1
}

# -----------------------------------------------------------------------------
# Bottom edge: accumulators per column
# -----------------------------------------------------------------------------
for {set c 0} {$c < $N} {incr c} {
    set pins {}
    for {set r 0} {$r < $N} {incr r} {
        set pins [concat $pins [slice acc_i $ACC_W [expr {$N * $N}] [expr {$r * $N + $c}]]]
    }
    place_bus bottom $pins $col_lo($c) $col_hi($c) $gap_x $die_x0 $die_x1
}

# -----------------------------------------------------------------------------
# Right edge: outputs per row
# -----------------------------------------------------------------------------
for {set r 0} {$r < $N} {incr r} {
    set pins {}
    for {set c 0} {$c < $N} {incr c} {
        set pins [concat $pins [slice out_q_o $ACC_W [expr {$N * $N}] [expr {$r * $N + $c}]]]
    }
    place_bus right $pins $row_lo($r) $row_hi($r) $gap_y $die_y0 $die_y1
}
