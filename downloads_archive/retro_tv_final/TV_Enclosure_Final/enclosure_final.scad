// =====================================================================
//  Pi + Arduino Retro-TV Enclosure  -  FINAL
//
//  For a bare 14" laptop panel driven by an LVDS controller board (the
//  board in your photo: HDMI/VGA/AV/USB connector strip, 183 x 40mm),
//  with a Raspberry Pi and an Arduino Uno inside.
//
//  Controls on the front: joystick (navigation + press = ENTER),
//  potentiometer (volume), power button (hold 2s = shutdown), speaker
//  grille. No IR receiver in this design.
//
//  What changed from v7:
//   - Screen opening resized to your measured panel: 315 x 179mm.
//   - Joystick hole enlarged to 27mm.
//   - Knob hole reduced to 5mm.
//   - Button hole changed from a 24mm circle to a 5 x 7mm oval, matching
//     your button's real size.
//   - Added a speaker grille on the front wall (placeholder size - see
//     SPEAKER PLACEHOLDER note below, confirm your driver's diameter).
//   - Added small back-cover plates for the knob and button: separate
//     flat parts that screw to the INSIDE of the front wall, so the
//     component is gripped from both sides instead of relying on the
//     thin front wall alone.
//   - Rear cable opening resized to the driver board's actual connector
//     strip: 183 x 40mm (was a generic 120 x 40mm guess).
//   - Added ventilation to the back wall (top wall and side walls
//     already had vents from v7).
//   - Added DRILL_MARKERS: set to true and every hole is overlaid with a
//     red marker, for a "here is where to cut" reference render. Leave
//     false for the real manufacturing export - the markers are not
//     part of the actual geometry.
//
//  *** SPEAKER PLACEHOLDER ***
//  No exact speaker diameter was given. The grille is sized to the
//  largest slot that fits the available space below the screen opening
//  without touching anything else: 100 x 44mm. If your driver is bigger
//  than that, tell me its real diameter and I will resize the grille and
//  re-export - do not cut this dimension on faith.
// =====================================================================
//  HOW TO USE
//  - Open in OpenSCAD (free, openscad.org)
//  - Set PART to render/export one piece at a time:
//      "assembly"     -> everything together, for viewing only
//      "side_frame"   -> the fused front+back+left+right wall piece
//      "bottom"       -> bottom panel (carries the Pi + Arduino standoffs)
//      "top"          -> top panel (vented lid)
//      "backplate"    -> the slide-in cover that pins the screen panel
//      "knob_cover"   -> small back-cover plate for the volume knob
//      "button_cover" -> small back-cover plate for the power button
//  - File > Export > Export as STL exports whatever PART is showing
// =====================================================================

PART = "assembly";
DRILL_MARKERS = false;   // true = overlay red markers at every hole

// ---------------------- CORE DIMENSIONS ----------------------
box_w      = 384;   // box width  (X)
box_h      = 260;   // box HEIGHT (Z)
box_d      = 215;   // box depth  (Y)
t          = 3;     // wall thickness
corner_sq  = 15;    // square reinforcement post at each of the 4 corners

// ---------------------- SCREW HOLES ----------------------
pilot_d      = 2.6;   // pilot hole INTO corner posts, for self-tapping M3
panel_hole_d = 3.4;   // clearance hole THROUGH the top/bottom panels, for M3
hole_depth   = 7;     // how deep a pilot hole goes into a corner post

// ---------------------- STANDOFFS (Pi / Arduino) ----------------------
standoff_h   = 6;
standoff_od  = 6.5;
pi_pilot_d   = 2.0;    // self-tapping M2.5
uno_pilot_d  = 2.5;    // self-tapping M3

pi_hole_spacing_x = 58;    // Raspberry Pi 4B / 3B+ mounting rectangle
pi_hole_spacing_y = 49;
uno_holes = [               // Arduino Uno R3 standard 4-hole pattern
    [15.24,  2.54],
    [15.24, 50.80],
    [66.04, 17.78],
    [66.04, 45.72]
];
pi_origin  = [20, 120];   // toward the back, clear of the joystick module
uno_origin = [130, 120];

// ---------------------- SCREEN OPENING ----------------------
// Visible (active) area of the panel - measured: 315 x 179mm.
screen_top_margin = 15;    // gap from the top edge of the frame
screen_w = 315;
screen_h = 179;
screen_x0 = (box_w - screen_w)/2;
screen_z0 = box_h - screen_top_margin - screen_h;

// ---------------------- PANEL + SLIDE-IN COVER ----------------------
panel_outline_w    = 324;  // panel OUTER width  - MEASURE YOURS if not confirmed
panel_outline_h    = 206;  // panel OUTER height - MEASURE YOURS if not confirmed
panel_t            = 6;    // panel thickness    - MEASURE YOURS if not confirmed
panel_bottom_extra = 20;   // opening bottom edge down to panel bottom edge
backplate_t = 3;           // cover thickness
fit_clr     = 0.4;         // sliding clearance
guide_t     = 2;           // side guide wall thickness
lip_t       = 2;           // rear retaining lip thickness
lip_w       = 10;          // how far each lip reaches over the cover edge
shelf_t     = 3;           // ledge thickness
ledge_w     = 40;          // ledge width (middle stays open for the panel's cable)

slot        = panel_t + backplate_t + 3*fit_clr;
panel_x0    = (box_w - panel_outline_w)/2;
shelf_z     = screen_z0 - panel_bottom_extra;
backplate_w  = panel_outline_w;
backplate_h  = panel_outline_h - shelf_t - 10;
backplate_x0 = panel_x0;
backplate_z0 = shelf_z + shelf_t;
backplate_y0 = t + panel_t + 2*fit_clr;

// ---------------------- FRONT CONTROL CLUSTER ----------------------
//  - Joystick: 27mm hole + 4x M2 pilot holes on a 19.5mm square
//  - Knob: 5mm hole
//  - Button: 5 x 7mm OVAL hole (not a circle - handled separately below)
joystick_hole_d        = 27;
joystick_mount_spacing = 19.5;   // MEASURE your module and adjust
joystick_mount_pilot_d = 2.0;    // self-tapping M2
knob_hole_d    = 5;
button_hole_w  = 5;    // oval width  (X)
button_hole_h  = 7;    // oval height (Z)
ctrl_pitch     = 40;              // center-to-center spacing
ctrl_center_x  = box_w/2;
ctrl_center_z  = 30;              // height above the floor

joystick_center = [ctrl_center_x - ctrl_pitch, ctrl_center_z];
knob_center     = [ctrl_center_x,              ctrl_center_z];
button_center   = [ctrl_center_x + ctrl_pitch, ctrl_center_z];

// round holes only (joystick, knob) - the oval button is cut separately
ctrl_positions = [
    [joystick_center[0], joystick_center[1], joystick_hole_d],
    [knob_center[0],     knob_center[1],     knob_hole_d]
];

// ---------------------- SPEAKER GRILLE (front wall) ----------------------
// PLACEHOLDER SIZE - see note at the top of the file. This is a row of
// slots, not a single big hole, so it stays within the space available
// below the screen opening without needing a huge single cutout.
speaker_w        = 100;   // overall grille zone width
speaker_h        = 44;    // overall grille zone height
// two grilles, flanking the control cluster - one left of the joystick,
// one right of the button, mirrored about the panel's horizontal center
speaker_center_x_right = ctrl_center_x + ctrl_pitch*2 + 30;   // right of the button
speaker_center_x_left  = 2*ctrl_center_x - speaker_center_x_right;   // mirrored, left of the joystick
speaker_centers_x = [speaker_center_x_left, speaker_center_x_right];
speaker_center_z = ctrl_center_z + 2;
speaker_slot_w   = 3;     // each slot's height (Z)
speaker_slot_gap = 4.5;   // spacing between slot centers
speaker_slot_margin = 8;  // clear margin left/right inside the grille zone

// ---------------------- BACK-COVER PLATES (knob + button) ----------------------
// Small flat parts, NOT part of the side_frame - screw to the inside of
// the front wall over the knob and button holes, so the thin wall is not
// the only thing gripping the component.
cover_t       = 3;    // plate thickness
cover_margin  = 10;   // how far the plate extends past the hole on each side
cover_screw_d = 2.0;  // self-tapping M2, mounting screws for each plate

knob_cover_w = knob_hole_d + 2*cover_margin;
knob_cover_h = knob_hole_d + 2*cover_margin;
button_cover_w = button_hole_w + 2*cover_margin;
button_cover_h = button_hole_h + 2*cover_margin;

// ---------------------- REAR CONNECTOR OPENING ----------------------
// Sized to the driver board's HDMI/VGA/AV/USB connector strip: 183 x 40mm.
cable_w  = 183;
cable_h  = 40;
cable_x0 = (box_w - cable_w)/2;
cable_z0 = 18;

// ---------------------- VENTILATION ----------------------
vent_w        = 4;      // slot width
vent_len      = 60;     // slot length
top_vent_x    = [49.5, 124.5, 199.5, 274.5];
top_vent_y    = [80, 92, 104, 116, 128, 140, 152, 164, 176];
side_vent_h   = 6;
side_vent_len = 50;
side_vent_y   = [30, 90, 148];
side_vent_z   = [205, 220, 235];
// back wall vents - two columns flanking the connector opening, clear of
// the corner posts and the connector cutout
back_vent_w   = 4;
back_vent_len = 50;
back_vent_x   = [40, 65, box_w-89, box_w-64];
back_vent_z   = [90, 105, 120, 135, 150, 165, 180, 195, 210];

// =====================================================================
//  CORNERS
// =====================================================================
corners = [[-1,-1], [1,-1], [-1,1], [1,1]];

function corner_x0(signX) = (signX < 0) ? 0 : box_w - corner_sq;
function corner_y0(signY) = (signY < 0) ? 0 : box_d - corner_sq;

// =====================================================================
//  ONE-PIECE SIDE FRAME
// =====================================================================
module side_frame() {
    color("lightgreen")
    union() {
        difference() {
            union() {
                difference() {
                    cube([box_w, box_d, box_h]);
                    translate([t, t, -1])
                        cube([box_w-2*t, box_d-2*t, box_h+2]);
                }
                for (c = corners)
                    translate([corner_x0(c[0]), corner_y0(c[1]), 0])
                        cube([corner_sq, corner_sq, box_h]);
            }

            for (c = corners) {
                cx = corner_x0(c[0]) + corner_sq/2;
                cy = corner_y0(c[1]) + corner_sq/2;
                translate([cx, cy, box_h - hole_depth])
                    cylinder(d=pilot_d, h=hole_depth+0.5, $fn=16);
                translate([cx, cy, -0.5])
                    cylinder(d=pilot_d, h=hole_depth+0.5, $fn=16);
            }

            // joystick + knob (round holes)
            for (c = ctrl_positions)
                translate([c[0], -0.5, c[1]])
                    rotate([-90,0,0])
                        cylinder(d=c[2], h=t+1, $fn=48);

            // button (oval hole)
            translate([button_center[0], -0.5, button_center[1]])
                rotate([-90,0,0])
                    scale([button_hole_w/button_hole_h, 1, 1])
                        cylinder(d=button_hole_h, h=t+1, $fn=48);

            // joystick module mounting screws
            for (dx = [-1,1]) for (dz = [-1,1])
                translate([joystick_center[0] + dx*joystick_mount_spacing/2,
                           -0.5,
                           joystick_center[1] + dz*joystick_mount_spacing/2])
                    rotate([-90,0,0])
                        cylinder(d=joystick_mount_pilot_d, h=t+1, $fn=12);

            // speaker grilles (left + right) - each a row of slots through the front wall
            for (sc = speaker_centers_x)
                for (i = [0 : floor((speaker_w - 2*speaker_slot_margin) / speaker_slot_gap)])
                    translate([sc - speaker_w/2 + speaker_slot_margin + i*speaker_slot_gap,
                               -0.5,
                               speaker_center_z - speaker_h/2])
                        rotate([-90,0,0])
                            linear_extrude(height=t+1)
                                hull() {
                                    translate([0, speaker_slot_w/2]) circle(d=speaker_slot_w, $fn=16);
                                    translate([0, speaker_h - speaker_slot_w/2]) circle(d=speaker_slot_w, $fn=16);
                                }

            // screen opening
            translate([screen_x0, -0.5, screen_z0])
                cube([screen_w, t+1, screen_h]);

            // rear connector opening, sized to the driver board
            translate([cable_x0, box_d - t - 0.5, cable_z0])
                cube([cable_w, t+1, cable_h]);

            // side wall vents
            for (sx = [-0.5, box_w - t - 0.5])
                for (vz = side_vent_z)
                    for (vy = side_vent_y)
                        translate([sx, vy, vz])
                            cube([t+1, side_vent_len, side_vent_h]);

            // back wall vents, flanking the connector opening
            for (vx = back_vent_x)
                for (vz = back_vent_z)
                    translate([vx, box_d - t - 0.5, vz])
                        cube([back_vent_w, t+1, back_vent_len]);
        }

        // panel + cover channel
        chan_z0 = shelf_z;
        chan_h  = box_h - chan_z0;
        for (side = [-1, 1]) {
            gx = (side < 0) ? panel_x0 - fit_clr - guide_t
                            : panel_x0 + panel_outline_w + fit_clr;
            translate([gx, t, chan_z0])
                cube([guide_t, slot + lip_t, chan_h]);
            lx = (side < 0) ? gx : gx + guide_t - lip_w;
            translate([lx, t + slot, chan_z0])
                cube([lip_w, lip_t, chan_h]);
            ex = (side < 0) ? gx + guide_t - 0.5
                            : panel_x0 + panel_outline_w + fit_clr - ledge_w + 0.5;
            translate([ex, t, chan_z0])
                cube([ledge_w, slot, shelf_t]);
        }
    }

    if (DRILL_MARKERS) drill_markers();
}

// =====================================================================
//  DRILL MARKERS - red highlights at every hole, reference only
// =====================================================================
module drill_markers() {
    color("red")
    union() {
        // corner screw holes (top + bottom, all 4 posts)
        for (c = corners) {
            cx = corner_x0(c[0]) + corner_sq/2;
            cy = corner_y0(c[1]) + corner_sq/2;
            translate([cx, cy, box_h - hole_depth])
                cylinder(d=pilot_d+1, h=hole_depth+2, $fn=16);
            translate([cx, cy, -1])
                cylinder(d=pilot_d+1, h=hole_depth+2, $fn=16);
        }
        // front wall: joystick, knob
        for (c = ctrl_positions)
            translate([c[0], -2, c[1]])
                rotate([-90,0,0])
                    cylinder(d=c[2]+2, h=t+4, $fn=48);
        // front wall: button (oval)
        translate([button_center[0], -2, button_center[1]])
            rotate([-90,0,0])
                scale([button_hole_w/button_hole_h, 1, 1])
                    cylinder(d=button_hole_h+2, h=t+4, $fn=48);
        // joystick mounting screws
        for (dx = [-1,1]) for (dz = [-1,1])
            translate([joystick_center[0] + dx*joystick_mount_spacing/2,
                       -2, joystick_center[1] + dz*joystick_mount_spacing/2])
                rotate([-90,0,0])
                    cylinder(d=joystick_mount_pilot_d+1.5, h=t+4, $fn=12);
        // speaker grille zone outlines (left + right)
        for (sc = speaker_centers_x)
            translate([sc - speaker_w/2 - 2, -2, speaker_center_z - speaker_h/2 - 2])
                cube([speaker_w+4, t+4, speaker_h+4]);
        // screen opening outline
        translate([screen_x0-2, -2, screen_z0-2])
            cube([screen_w+4, t+4, 4]);   // bottom edge marker
        // rear connector opening
        translate([cable_x0-2, box_d-t-2, cable_z0-2])
            cube([cable_w+4, t+4, cable_h+4]);
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
        for (vx = top_vent_x)
            for (vy = top_vent_y)
                translate([vx, vy, -0.5])
                    cube([vent_len, vent_w, t+1]);
    }
    if (DRILL_MARKERS)
        color("red")
        for (c = corners) {
            cx = corner_x0(c[0]) + corner_sq/2;
            cy = corner_y0(c[1]) + corner_sq/2;
            translate([cx, cy, -1])
                cylinder(d=panel_hole_d+1.5, h=t+2, $fn=16);
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

// ---------------------- SLIDE-IN COVER ----------------------
module backplate() {
    color("gray")
    cube([backplate_w, backplate_t, backplate_h]);
}

// ---------------------- BACK-COVER PLATES ----------------------
module knob_cover() {
    color("orange")
    difference() {
        translate([-knob_cover_w/2, -knob_cover_h/2, 0])
            cube([knob_cover_w, knob_cover_h, cover_t]);
        translate([0, 0, -0.5])
            cylinder(d=knob_hole_d, h=cover_t+1, $fn=32);
        for (dx=[-1,1]) for (dy=[-1,1])
            translate([dx*(knob_cover_w/2-4), dy*(knob_cover_h/2-4), -0.5])
                cylinder(d=cover_screw_d, h=cover_t+1, $fn=12);
    }
}

module button_cover() {
    color("orange")
    difference() {
        translate([-button_cover_w/2, -button_cover_h/2, 0])
            cube([button_cover_w, button_cover_h, cover_t]);
        translate([0, 0, -0.5])
            scale([button_hole_w/button_hole_h, 1, 1])
                cylinder(d=button_hole_h, h=cover_t+1, $fn=32);
        for (dx=[-1,1]) for (dy=[-1,1])
            translate([dx*(button_cover_w/2-4), dy*(button_cover_h/2-4), -0.5])
                cylinder(d=cover_screw_d, h=cover_t+1, $fn=12);
    }
}

// =====================================================================
//  ASSEMBLY
// =====================================================================
EXPLODE = 0;

module assembly() {
    side_frame();
    translate([0, 0, -t-EXPLODE])     bottom_panel();
    translate([0, 0, box_h+EXPLODE])  top_panel();
    translate([backplate_x0, backplate_y0 + EXPLODE, backplate_z0])
        backplate();
    // back-cover plates, shown behind the front wall where they mount
    translate([knob_center[0], t - EXPLODE, knob_center[1]])
        rotate([-90,0,0]) knob_cover();
    translate([button_center[0], t - EXPLODE, button_center[1]])
        rotate([-90,0,0]) button_cover();
    // ghost of the bare screen panel, for checking fit - NOT a printed part
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
else if (PART == "knob_cover") knob_cover();
else if (PART == "button_cover") button_cover();
else assembly();
