# 22-inch enclosure: design review and measurement hold
Reviewed 2026-10-10. **Concept only — not released for cutting or drilling.**
All dimensions below are millimetres (mm). No new physical measurements were supplied.

## Current files
- `enclosure_22in.scad` and `enclosure_work/enclosure_22in.scad`: identical at review; current 22-inch model sources. Keep both synchronized.
- `enclosure_work/final22/`: existing 22-inch exports, as recorded in PROJECT_LOG.md; not regenerated or visually verified in this review.
- `enclosure_work/draw_bottom_22in.py` and `draw_mainbody_bottom_22in.py`: 22-inch drawing scripts; manually repeated dimensions and Windows-specific paths/fonts.
- `enclosure_final.scad`, its work copy, `enclosure_work/final/`, root carpenter cut sheet/email and the older README enclosure instructions: historical 14-inch design, not current cutting instructions.
- `downloads_archive/`: historical snapshots; preserve.

Latest enclosure decision in the log is 2026-10-04: replace the 14-inch bare panel with a nominal 22-inch HDMI monitor, stand removed. No LVDS board is required for that arrangement. There is no later measured monitor specification in the reviewed log.

## Current model, not measured hardware
| Item | Model value | Status |
|---|---|---|
| Frame width × height × depth | 560 × 390 × 215 | Provisional |
| Complete assembly height | 396 | Derived: 390 frame + two external 3 mm panels |
| Wall/panel thickness; corner posts | 3; 15 × 15 | Material and strength unverified |
| Screen opening | 477 × 268 | Explicit monitor placeholder |
| Monitor outer width × height × depth | 510 × 305 × 55 | Explicit monitor placeholder |
| Ledge underside / support surface above frame base | 70 / 73 | Derived |
| Rear cable opening | 120 × 40 | Provisional; plug passage unverified |
| Joystick / knob / button openings | diameter 27 / diameter 5 / oval 5 × 7 | Inherited; reconfirm actual current components |
| Joystick mounting pattern | 19.5 square; diameter 2 pilots | Explicit placeholder |
| Two speaker grille zones | 100 × 44 each | Explicit placeholders |

The monitor sits behind the front opening on two ledges, between side guides and a retaining plate. Controls run joystick–volume–power across the lower centre, flanked by two speaker grilles. Pi and Uno standoffs are on the removable bottom toward the rear. Vents are modeled in the top, sides and rear.

## Checks and unresolved design problems
Source review and arithmetic only; OpenSCAD is unavailable in this environment. Earlier log statements about manifold solids are historical results, not validation performed here.
- Joystick screw-centre radius is sqrt(2) × 19.5 / 2 = 13.789 mm. With a 13.5 mm opening radius and 1 mm pilot radius, each pilot overlaps the main opening by about 0.711 mm. Actual module dimensions are needed before designing a mounting bracket.
- Assembly places panels outside the 390 mm frame: total 396 mm. Existing 390 mm descriptions must distinguish frame height from finished height.
- The 12 mm corner screw through a 3 mm panel nominally enters the post 9 mm, while the pilot is only 7 mm deep. Fastener type, pilot depth and material must be resolved with the carpenter.
- The joined-top option inherits a historical 14-inch construction decision. Confirm whether any 22-inch body has actually been built. Top-loading monitor/cover removal cannot be assumed with a fixed top; bottom insertion around the ledges is unverified.
- The backplate has clearance holes but the source provides no corresponding dedicated threaded mounts/pilot bosses. Screw engagement and tool access are unresolved.
- The monitor ghost is modeled 302 mm high (305 minus the 3 mm shelf), not its stated full 305 mm envelope. A real monitor envelope, bezel offsets and connectors must replace this approximation.
- Rear vent cuts are 50 mm tall on 15 mm vertical spacing, so they overlap into long slots. Structural strength and monitor ventilation must be checked.
- Speaker mounting, amplifier placement, board connector envelopes, wire paths, cable strain relief and monitor weight support are not validated. Standard board hole patterns do not prove fit of the actual boards.
- 0.4 mm sliding clearance and 3 mm walls are CAD assumptions, not approved woodworking tolerances or material choices.
- SCAD header contains inherited 14-inch values (315 × 179 screen, 183 × 40 connector strip); executable 22-inch parameters supersede those comments. No geometry changed during this intake review.

## Measurements to collect before final dimensions
Please provide mm and photos with a ruler where useful. Label estimates explicitly.
1. Monitor make/model; stand removed outer width × height × maximum depth; weight; whether casing stays intact.
2. Lit image width × height and offsets from all four outer edges (bezel widths).
3. Rear and side photos: HDMI/power ports, buttons, vents, stand attachment, and any VESA holes. Give hole centre distances and position relative to monitor edges; screw specification/depth from the monitor documentation.
4. With intended HDMI/power cables plugged in, required depth and direction of cable bends and plug dimensions.
5. Joystick PCB width × height × depth, hole diameters and centre spacing, stick travel, and protrusion wanted at front.
6. Volume control and power switch: mounting shaft/body sizes, required cutouts, usable mounting length, rear depth including wires, and any mounting holes. Confirm these are the same components as the old design.
7. Each speaker: count, outer size, required cutout, mounting-hole centres/diameters, rear depth; amplifier size and holes if used.
8. Pi and Uno: actual board/case/cooler dimensions, mounting pattern and space with USB, HDMI, power and GPIO cables installed.
9. Carpenter: material, actual sheet thickness, joint method, available screws, and what has already been cut/glued (with dimensions/photos).
10. Desired access: removable top/back/bottom, SD-card/USB access, and any maximum cabinet size.

## Next step after measurements
Agree mounting and service access; update both current sources, add component envelopes and checks, then regenerate affected exports and dimensioned carpenter drawings consistently. Include view/origin labels, mm, material, joints, hole centres/diameters, fasteners and revision/status on drawings. Verify insertion/removal and screwdriver access, port bends, speaker clearance and airflow before approving final dimensions. No current drawing is manufacturing-ready.
