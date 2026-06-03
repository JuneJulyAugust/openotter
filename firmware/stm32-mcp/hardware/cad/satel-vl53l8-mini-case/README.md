# SATEL-VL53L8 Mini-PCB Case

This directory contains generated artifacts for a bottom-mounted case for the
broken-off SATEL-VL53L8 mini-PCB sensor head.

For the recommended first car deployment with the complete SATEL carrier board,
use the sibling `../satel-vl53l8-full-carrier-case/` model instead.

## Source

The source model is the repo-level CadQuery generator:

```text
../vl53l8_cases_cadquery.py
```

CadQuery or build123d should be used for future repo-native case updates.

Coordinate convention:

- `Z=0` is the flat bottom mounting face against the car.
- `+Z` is the VL53L8 optical direction through the lid aperture.
- `+Y` is the harness exit direction.

## Mechanical Features

- Flat bottom face for VHB tape or direct car-surface mounting.
- Side ears with M2 through-holes for screw mounting.
- PCB ledges, side rails, and an end stop keep the mini-PCB steady without
  loading the soldered 0.8 x 1.6 mm pads.
- Lid retainer pads lightly capture PCB edge areas when the case is closed.
- Harness tie slots and a printed rear strain bar keep cable load away from the
  30 AWG pigtails.
- The harness exits behind the sensor and outside the field-of-view cone.

## Status

This is a v0 mechanical artifact. The SATEL Gerber ZIP or STEP package is the
preferred source for exact board outline, but the ST download endpoint timed out
from the current development environment. The defaults are therefore
conservative and must be updated after measuring the snapped-off mini-PCB with
calipers.

## Generate

Install the CAD dependencies in the project `.venv`, then regenerate all
full-carrier and mini-PCB artifacts from the shared script:

```bash
/Users/fang/projects/openotter/.venv/bin/python -m pip install \
  -r ../requirements.txt
```

```bash
MPLCONFIGDIR=/private/tmp/matplotlib-openotter \
  /Users/fang/projects/openotter/.venv/bin/python \
  ../vl53l8_cases_cadquery.py
```

## Generated Artifacts

```text
stl/satel_vl53l8_mini_base.stl
stl/satel_vl53l8_mini_lid.stl
step/satel_vl53l8_mini_base.step
step/satel_vl53l8_mini_lid.step
step/satel_vl53l8_mini_assembly.step
renders/satel_vl53l8_mini_cadquery_preview.png
```

![Mini-PCB CadQuery preview](renders/satel_vl53l8_mini_cadquery_preview.png)

## Print

- Print the base with the flat bottom mounting face on the bed.
- Print the lid with the outside optical face on the bed.
- PETG is preferred for car installation.
- Keep the optical opening clean and free of stringing.
- Confirm the lid retainer pads contact only PCB edge areas.
- Keep screw heads, bumper lips, wires, and tape edges outside the FOV preview
  cone.
- Use M2 screws through the side ears, or use 3M VHB tape on the flat bottom.

## Electrical Warning

The snapped-off mini-PCB does not expose the same interface as the full SATEL
carrier `J2` header. Do not wire IOT01A1 5 V directly to the mini-PCB. Validate
`DUT_AVDD`, `DUT_IOVDD`, and the GPIO voltage domain before using this case on
the car.
