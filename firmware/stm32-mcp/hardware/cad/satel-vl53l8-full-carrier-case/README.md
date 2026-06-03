# SATEL-VL53L8 Full-Carrier Case

This directory contains generated artifacts for a bottom-mounted case that
keeps the complete SATEL-VL53L8 carrier board intact.

The full carrier is the safer near-term deployment path because it keeps the
SATEL regulators, level translators, and 2.54 mm J1/J2 carrier pads in use.

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
- PCB ledges, side rails, and an end stop keep the SATEL carrier steady without
  drilling the board.
- Lid retainer pads lightly capture PCB edge areas when the case is closed.
- Harness tie slots and a printed rear strain bar keep cable load away from the
  soldered pigtails.
- The harness exits behind the sensor and outside the field-of-view cone.

## Status

This is a v0 mechanical artifact. The ST product page lists STEP CAD and Gerber
resources, but the ST ZIP download timed out from this development environment.
The defaults are therefore approximate and must be updated from either the ST
CAD/Gerber package or caliper measurements before final printing.

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
stl/satel_vl53l8_full_carrier_base.stl
stl/satel_vl53l8_full_carrier_lid.stl
step/satel_vl53l8_full_carrier_base.step
step/satel_vl53l8_full_carrier_lid.step
step/satel_vl53l8_full_carrier_assembly.step
renders/satel_vl53l8_full_carrier_cadquery_preview.png
```

![Full carrier CadQuery preview](renders/satel_vl53l8_full_carrier_cadquery_preview.png)

## Intended Harness

For car use, avoid tall loose Dupont jumpers. Preferred assembly:

1. Solder short 28 AWG silicone pigtails to the SATEL J1/J2 through-hole pads.
2. Bundle the pigtails through the case cable exit.
3. Terminate the bundle into a keyed JST-GH connector outside the case, or
   capture a small JST-GH adapter board in the rear cable bay.
4. Use a matching JST-GH harness to the IOT01A1 adapter shield.

## Print

- Print the base with the flat bottom mounting face on the bed.
- Print the lid with the outside optical face on the bed.
- PETG is preferred for car installation.
- Do not let the lid touch solder joints, installed pin headers, or the optical
  package.
- Confirm the lid retainer pads contact only PCB edge areas.
- Keep screw heads, bumper lips, wires, and tape edges outside the FOV preview
  cone.
- Use M2 screws through the side ears, or use 3M VHB tape on the flat bottom.
