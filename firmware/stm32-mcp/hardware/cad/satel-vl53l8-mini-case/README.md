# SATEL-VL53L8 Mini-PCB Case

This directory contains a first parametric enclosure for a broken-off
SATEL-VL53L8 mini-PCB sensor head.

## Files

- `satel_vl53l8_mini_case.scad` - OpenSCAD source for a two-piece tray and
  optical-window lid.

## Status

This is a v0 mechanical artifact. The SATEL Gerber ZIP is the preferred source
for exact board outline, but the ST download endpoint was not reachable from
the current sandbox session. The defaults are therefore conservative and must be
updated after measuring the snapped-off mini-PCB with calipers.

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
openscad -D 'part="base"' -o satel_vl53l8_mini_case_base.stl satel_vl53l8_mini_case.scad
openscad -D 'part="lid"'  -o satel_vl53l8_mini_case_lid.stl  satel_vl53l8_mini_case.scad
```

Use `part = "assembly"` inside OpenSCAD for a visual fit preview.

## Print

- Print the base with the flat tape face on the bed.
- Print the lid with the outside face on the bed.
- PETG is preferred for car installation.
- Keep the optical opening clean and free of stringing.
- Use M2 screws through the side ears, or use 3M VHB tape on the flat underside.

## Electrical Warning

The snapped-off mini-PCB does not expose the same interface as the full SATEL
carrier `J2` header. Do not wire IOT01A1 5 V directly to the mini-PCB. Validate
`DUT_AVDD`, `DUT_IOVDD`, and the GPIO voltage domain before using this case on
the car.
