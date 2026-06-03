# SATEL-VL53L8 Mini-PCB Case

This directory contains a first parametric enclosure for a broken-off
SATEL-VL53L8 mini-PCB sensor head.

For the recommended first car deployment with the complete SATEL carrier board,
use the sibling `../satel-vl53l8-full-carrier-case/` model instead.

## Files

- `satel_vl53l8_mini_case.scad` - OpenSCAD source for a two-piece tray and
  optical-window lid.

## Mechanical Features

- Printed PCB ledges, side rails, and an end stop keep the mini-PCB steady
  without loading the soldered 0.8 x 1.6 mm pads.
- Underside lid retainer pads lightly capture PCB edge areas when the case is
  screwed closed.
- Harness tie slots and a printed rear strain bar keep cable load away from
  the 30 AWG pigtails.
- Side ears accept M2 case/mount screws.
- `part = "assembly"` shows preview-only harness wires, car mount surface, and
  field-of-view cone. Do not export the assembly as a printable part.

## Status

This is a v0 mechanical artifact. The SATEL Gerber ZIP or STEP package is the
preferred source for exact board outline, but the ST download endpoint timed out
from the current development environment. The defaults are therefore
conservative and must be updated after measuring the snapped-off mini-PCB with
calipers.

Edit these OpenSCAD parameters before a final print:

```scad
board_w = 20.0;
board_h = 22.0;
board_t = 1.0;
sensor_x = 0.0;
sensor_y = -1.5;
optic_opening = 14.0;
```

## Export

Install OpenSCAD, then export each printable part:

```bash
openscad --export-format binstl -D 'part="base"' -o stl/satel_vl53l8_mini_case_base.stl satel_vl53l8_mini_case.scad
openscad --export-format binstl -D 'part="lid"'  -o stl/satel_vl53l8_mini_case_lid.stl  satel_vl53l8_mini_case.scad
openscad --export-format binstl -D 'part="mount_plate"' -o stl/satel_vl53l8_mini_mount_plate.stl satel_vl53l8_mini_case.scad
```

Use `part = "assembly"` inside OpenSCAD for a visual fit preview. The assembly
preview includes the harness path, a gray car mounting plane, and a transparent
field-of-view cone to catch obvious occlusion issues.

Generated exports are stored in:

```text
stl/satel_vl53l8_mini_case_base.stl
stl/satel_vl53l8_mini_case_lid.stl
stl/satel_vl53l8_mini_mount_plate.stl
renders/satel_vl53l8_mini_stl_preview.png
```

The PNG preview is rendered from the OpenSCAD STL exports by:

```bash
MPLCONFIGDIR=/private/tmp/matplotlib-openotter \
  /Users/fang/projects/openotter/.venv/bin/python \
  ../render_stl_previews.py
```

Native OpenSCAD PNG rendering needs a local macOS OpenGL context. It failed in
the remote session with `Unable to create NSOpenGLContext`, so the committed PNG
preview uses the STL-based renderer above.

![Mini-PCB STL preview](renders/satel_vl53l8_mini_stl_preview.png)

## Print

- Print the base with the flat tape face on the bed.
- Print the lid with the outside face on the bed.
- PETG is preferred for car installation.
- Keep the optical opening clean and free of stringing.
- Confirm the lid retainer pads contact only PCB edge areas.
- Keep screw heads, bumper lips, wires, and tape edges outside the FOV preview
  cone.
- Use M2 screws through the side ears, or use 3M VHB tape on the flat underside.

## Electrical Warning

The snapped-off mini-PCB does not expose the same interface as the full SATEL
carrier `J2` header. Do not wire IOT01A1 5 V directly to the mini-PCB. Validate
`DUT_AVDD`, `DUT_IOVDD`, and the GPIO voltage domain before using this case on
the car.
