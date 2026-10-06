// =====================================================================
//  Pi + Arduino Retro-TV Enclosure v6 - sized for a BARE 14" LAPTOP PANEL
//  (N140BGE-class, 1366x768, driven by an LVDS controller board).
//
//  Same construction as v5: one fused front/back/left/right frame with
//  corner posts, separate top and bottom panels, and a slide-in cover that
//  pins the panel behind the screen opening.
//
//  What changed from v5:
//   - Screen opening 310 x 174 mm (14" 16:9 visible area), was 231 x 130.
//   - Box 384 (W) x 215 (D) x 260 (H), was 305 x 215 x 215.
//   - Panel and cover now slide into ONE channel, cover directly behind
//     the panel. Side guides hold the panel centred, two ledges hold it up.
//   - Control hole sizes and spacing are unchanged.
//   - Driver board mounting is NOT included yet - add it once the board
//     arrives and you can measure it.
// =====================================================================
//  HOW TO USE
//  - Open in OpenSCAD (free, openscad.org)
//  - Set PART to render/export one piece at a time:
//      "assembly"   -> everything shown together, for viewing only
//      "side_frame" -> the ONE fused front+back+left+right wall piece
//      "bottom"     -> bottom panel (has the Pi + Arduino standoffs)
//      "top"        -> top panel
//      "backplate"  -> the panel slide-in cover
//  - File > Export > Export as STL exports whatever PART is showing
// =====================================================================

PART = "assembly";

// ---------------------- CORE DIMENSIONS ----------------------
box_w      = 384;   // box width  (X)
box_h      = 260;   // box HEIGHT (Z)
box_d      = 215;   // box depth  (Y)
t          = 3;     // wall thickness
corner_sq  = 15;    // small square reinforcement post at each of the 4 corners (mm)

// ---------------------- SCREW HOLES ----------------------
pilot_d      = 2.6;   // pilot hole drilled INTO corner posts, for self-tapping M3
panel_hole_d = 3.4;   // clearance hole THROUGH panels/backplate, for M3
hole_depth   = 7;     // how deep a pilot hole goes into a corner post
back_hole_f  = [0.35, 0.65];  // fractions of box_h - backplate attachment hole heights

// ---------------------- STANDOFFS (Pi / Arduino) ----------------------
standoff_h   = 6;
standoff_od  = 6.5;
pi_pilot_d   = 2.0;    // self-tapping M2.5
uno_pilot_d  = 2.5;    // self-tapping M3

pi_hole_spacing_x = 58;    // Raspberry Pi 4B / 3B+ mounting rectangle
pi_hole_spacing_y = 49;
uno_holes = [               // Arduino Uno R3 standard 4-hole pattern
    [15.24, 2.54],
    [15.24, 50.80],
    [66.04, 17.78],
    [66.04, 45.72]
];
pi_origin  = [20, 10];
uno_origin = [115, 8];

// ---------------------- RETRO-TV SCREEN OPENING ----------------------
// Visible area of a 14" 16:9 panel. Measure your panel's active area and
// change these two numbers if it differs; everything else follows.
screen_top_margin = 15;    // gap from the top edge of the frame
screen_w = 310;
screen_h = 174;
screen_x0 = (box_w - screen_w)/2;
screen_z0 = box_h - screen_top_margin - screen_h;

// ---------------------- PANEL SLIDE-IN COVER (behind the screen hole) ----------------------
// The panel and its cover slide down TOGETHER into one channel behind the
// front wall: front wall | panel | cover | rear lips. The cover sits
// directly against the back of the panel, nothing in between.
// The panel rests on two ledges, and side guides hold it centred.
panel_outline_w    = 324;  // panel outer width  (typical 14" ~323.5) - MEASURE YOURS
panel_outline_h    = 206;  // panel outer height (typical 14" ~205.4) - MEASURE YOURS
panel_t            = 6;    // panel thickness                          - MEASURE YOURS
panel_bottom_extra = 20;   // opening bottom edge down to panel bottom edge - MEASURE YOURS
backplate_t = 3;           // cover thickness
fit_clr     = 0.4;         // sliding clearance each side of the panel and cover
guide_t     = 2;           // side guide wall thickness
lip_t       = 2;           // rear retaining lip thickness
lip_w       = 10;          // how far each lip reaches over the edge of the cover
shelf_t     = 3;           // ledge thickness
ledge_w     = 40;          // width of each ledge (middle stays open for the panel cable)

slot        = panel_t + backplate_t + 3*fit_clr;   // channel depth (Y): clearance in front of the panel, between panel and cover, and behind the cover
panel_x0    = (box_w - panel_outline_w)/2;
shelf_z     = screen_z0 - panel_bottom_extra;      // panel rests here
backplate_w  = panel_outline_w;
backplate_h  = panel_outline_h - shelf_t - 10;     // stops 10mm below the panel top
backplate_x0 = panel_x0;
backplate_z0 = shelf_z + shelf_t;                  // cover rests on the ledges
backplate_y0 = t + panel_t + 2*fit_clr;            // directly behind the panel


// ---------------------- RETRO-TV CONTROL CLUSTER (sizes unchanged) ----------------------
//  - Joystick: 20mm hole + 4x M2 pilot holes on a 19.5mm square
//  - Potentiometer: 7mm hole
//  - Button: 24mm hole
joystick_hole_d = 20;
joystick_mount_spacing = 19.5;
joystick_mount_pilot_d = 2.0;    // self-tapping M2
knob_hole_d     = 7;
button_hole_d   = 24;
ctrl_gap        = 25;
ctrl_pitch      = 40;
ctrl_center_x   = box_w/2;
ctrl_center_z   = 30;
ctrl_positions = [
    [ctrl_center_x - ctrl_pitch, ctrl_center_z, joystick_hole_d],
    [ctrl_center_x,              ctrl_center_z, knob_hole_d],
    [ctrl_center_x + ctrl_pitch, ctrl_center_z, button_hole_d]
];
joystick_center = ctrl_positions[0];

// =====================================================================
//  CORNERS  - posts = [signX, signY]  (-1 = near 0, +1 = near box_w/box_d)
// =====================================================================
corners = [[-1,-1], [1,-1], [-1,1], [1,1]];

function corner_x0(signX) = (signX < 0) ? 0 : box_w - corner_sq;
function corner_y0(signY) = (signY < 0) ? 0 : box_d - corner_sq;

// =====================================================================
//  ONE-PIECE SIDE FRAME (front + back + left + right, fused)
// =====================================================================
module side_frame() {
    color("lightgreen")
    union() {
        difference() {
            union() {
                // hollow perimeter tube
                difference() {
                    cube([box_w, box_d, box_h]);
                    translate([t, t, -1])
                        cube([box_w-2*t, box_d-2*t, box_h+2]);
                }
                // 4 solid corner posts, fused into the tube
                for (c = corners)
                    translate([corner_x0(c[0]), corner_y0(c[1]), 0])
                        cube([corner_sq, corner_sq, box_h]);
            }

            // top + bottom pilot holes at every corner post
            for (c = corners) {
                cx = corner_x0(c[0]) + corner_sq/2;
                cy = corner_y0(c[1]) + corner_sq/2;
                translate([cx, cy, box_h - hole_depth])
                    cylinder(d=pilot_d, h=hole_depth+0.5, $fn=16);
                translate([cx, cy, -0.5])
                    cylinder(d=pilot_d, h=hole_depth+0.5, $fn=16);
            }

            // retro-TV control cluster, through the front wall (y: 0..t)
            for (c = ctrl_positions)
                translate([c[0], -0.5, c[1]])
                    rotate([-90,0,0])
                        cylinder(d=c[2], h=t+1, $fn=48);

            // joystick module mounting screws (4x, around the joystick hole)
            for (dx = [-1,1]) for (dz = [-1,1])
                translate([joystick_center[0] + dx*joystick_mount_spacing/2,
                           -0.5,
                           joystick_center[1] + dz*joystick_mount_spacing/2])
                    rotate([-90,0,0])
                        cylinder(d=joystick_mount_pilot_d, h=t+1, $fn=12);

            // screen opening, through the front wall
            translate([screen_x0, -0.5, screen_z0])
                cube([screen_w, t+1, screen_h]);
        }

        // panel + cover channel, one on each side. Each side is a guide wall
        // (joined to the front wall) with a lip at the back that reaches
        // over the cover's edge. Panel and cover drop in from the top and
        // slide down until they rest on the ledges.
        chan_z0 = shelf_z;
        chan_h  = box_h - chan_z0;
        for (side = [-1, 1]) {
            // guide wall, just outside the panel edge
            gx = (side < 0) ? panel_x0 - fit_clr - guide_t
                            : panel_x0 + panel_outline_w + fit_clr;
            translate([gx, t, chan_z0])
                cube([guide_t, slot + lip_t, chan_h]);
            // rear lip, reaching inward over the cover edge
            lx = (side < 0) ? gx : gx + guide_t - lip_w;
            translate([lx, t + slot, chan_z0])
                cube([lip_w, lip_t, chan_h]);
            // ledge the panel and cover rest on
            ex = (side < 0) ? gx + guide_t - 0.5
                            : panel_x0 + panel_outline_w + fit_clr - ledge_w + 0.5;
            translate([ex, t, chan_z0])
                cube([ledge_w, slot, shelf_t]);
        }
    }
}

// =====================================================================
//  TOP / BOTTOM PANELS
// =====================================================================
module top_panel() {
    color("plum")
    difference() {
        cube([box_w, box_d, t]);
        for (c = corners) {
            cx = corner_x0(c[0]) + corner_sq/2;
            cy = corner_y0(c[1]) + corner_sq/2;
            translate([cx, cy, -0.5])
                cylinder(d=panel_hole_d, h=t+1, $fn=16);
        }
    }
}

module bottom_panel() {
    color("plum")
    union() {
        difference() {
            cube([box_w, box_d, t]);
            for (c = corners) {
                cx = corner_x0(c[0]) + corner_sq/2;
                cy = corner_y0(c[1]) + corner_sq/2;
                translate([cx, cy, -0.5])
                    cylinder(d=panel_hole_d, h=t+1, $fn=16);
            }
        }
        pi_standoffs();
        uno_standoffs();
    }
}

module pi_standoffs() {
    translate([pi_origin[0], pi_origin[1], t])
        for (p = [[0,0],[0,pi_hole_spacing_y],[pi_hole_spacing_x,0],[pi_hole_spacing_x,pi_hole_spacing_y]])
            translate([p[0], p[1], 0])
                difference() {
                    cylinder(d=standoff_od, h=standoff_h, $fn=24);
                    translate([0,0,-0.5]) cylinder(d=pi_pilot_d, h=standoff_h+1, $fn=16);
                }
}

module uno_standoffs() {
    translate([uno_origin[0], uno_origin[1], t])
        for (p = uno_holes)
            translate([p[0], p[1], 0])
                difference() {
                    cylinder(d=standoff_od, h=standoff_h, $fn=24);
                    translate([0,0,-0.5]) cylinder(d=uno_pilot_d, h=standoff_h+1, $fn=16);
                }
}

// ---------------------- PANEL COVER (slides into the rails) ----------------------
module backplate() {
    color("gray")
    cube([backplate_w, backplate_t, backplate_h]);
}

// =====================================================================
//  ASSEMBLY
// =====================================================================
EXPLODE = 0;

module assembly() {
    side_frame();
    translate([0, 0, -t-EXPLODE])       bottom_panel();
    translate([0, 0, box_h+EXPLODE])    top_panel();
    translate([backplate_x0, backplate_y0 + EXPLODE, backplate_z0])
        backplate();
    // ghost of the bare panel, for checking the fit (not exported as a part)
    color("steelblue", 0.7)
    translate([panel_x0, t + fit_clr + EXPLODE/2, shelf_z + shelf_t])
        cube([panel_outline_w, panel_t, panel_outline_h - shelf_t]);
}

// =====================================================================
//  RENDER SELECTOR
// =====================================================================
if (PART == "side_frame") side_frame();
else if (PART == "bottom") bottom_panel();
else if (PART == "top") top_panel();
else if (PART == "backplate") backplate();
else assembly();
