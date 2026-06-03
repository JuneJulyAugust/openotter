# SATEL-VL53L8 Full-Carrier Case

This directory contains a first parametric enclosure for using the complete
SATEL-VL53L8 carrier board on the RC car.

The full carrier is the safer near-term deployment path because it keeps the
SATEL regulators, level translators, and 2.54 mm J1/J2 carrier pads in use.

## Files

- `satel_vl53l8_full_carrier_case.scad` - OpenSCAD source for a two-piece
  full-carrier tray, optical-window lid, and optional mount plate.

## Mechanical Features

- Printed PCB ledges, side rails, and an end stop keep the SATEL carrier steady
  without drilling the board.
- Underside lid retainer pads lightly capture PCB edge areas when the case is
  screwed closed.
- Harness tie slots and a printed rear strain bar keep cable load away from
  the soldered pigtails.
- Side ears accept M2 case/mount screws.
- `part = "assembly"` shows preview-only harness wires, car mount surface, and
  field-of-view cone. Do not export the assembly as a printable part.

## Status

This is a v0 mechanical artifact. The ST product page lists STEP CAD and Gerber
resources, but the ST ZIP download timed out from this development environment.
The defaults are therefore approximate and must be updated from either the ST
CAD/Gerber package or caliper measurements before final printing.

Edit these OpenSCAD parameters first:

```scad
board_w = 30.5;
board_h = 66.0;
board_t = 1.6;
sensor_x = 0.0;
sensor_y = -21.0;
header_clearance_z = 8.0;
optic_opening = 18.0;
```

## Export

Install OpenSCAD, then export each printable part:

```bash
openscad -D 'part="base"' -o satel_vl53l8_full_carrier_case_base.stl satel_vl53l8_full_carrier_case.scad
openscad -D 'part="lid"'  -o satel_vl53l8_full_carrier_case_lid.stl  satel_vl53l8_full_carrier_case.scad
openscad -D 'part="mount_plate"' -o satel_vl53l8_full_carrier_mount_plate.stl satel_vl53l8_full_carrier_case.scad
```

Use `part = "assembly"` inside OpenSCAD for a visual fit preview. The assembly
preview includes the harness path, a gray car mounting plane, and a transparent
field-of-view cone to catch obvious occlusion issues.

## Intended Harness

For car use, avoid tall loose Dupont jumpers. Preferred assembly:

1. Solder short 28 AWG silicone pigtails to the SATEL J1/J2 through-hole pads.
2. Bundle the pigtails through the case cable exit.
3. Terminate the bundle into a keyed JST-GH connector outside the case, or
   capture a small JST-GH adapter board in the rear cable bay.
4. Use a matching JST-GH harness to the IOT01A1 adapter shield.

## Print

- Print the base with the flat mounting face on the bed.
- Print the lid with the outside optical face on the bed.
- PETG is preferred for car installation.
- Do not let the lid touch solder joints, installed pin headers, or the optical
  package.
- Confirm the lid retainer pads contact only PCB edge areas.
- Keep screw heads, bumper lips, wires, and tape edges outside the FOV preview
  cone.
- Use M2 screws through the side ears, or use 3M VHB tape on the flat rear
  mounting plate.
