# 12 - SATEL-VL53L8 Mechanical Integration

This document covers the deployment hardware path after the bench Dupont-wire
prototype: cable harness, board-side connection, solder strain relief, and a
first printable enclosure for front/rear SATEL-VL53L8 sensors.

## Current Problem

The photo-based prototype works for firmware bring-up, but it is not suitable
for a moving RC car:

- long Dupont jumpers are stiff and unsupported;
- the SATEL board is held by the wires, not by a mechanical reference;
- the IOT01A1 header connections can be bumped loose;
- the sensor has no strain relief, no datum, and no repeatable front/rear
  pointing angle.

The deployment target should be a short local solder joint at the SATEL side,
a flexible locking harness, and a small printed enclosure that mounts to the RC
car with either tape or screws.

## Critical Electrical Choice: Full Carrier vs. Snap-Off Mini-PCB

There are two different SATEL electrical interfaces.

### Full SATEL carrier board

Use this for the current one-sensor and first two-sensor validation:

- accepts `EXT_5V0` on `J2 pin 11`;
- provides on-board regulators;
- provides level shifting between the STM32 3.3 V side and the VL53L8 side;
- exposes comfortable 2.54 mm header pads.

This is mechanically larger but much safer for the v1.2.0 validation gate.

### Broken-off mini-PCB

The ST data brief says the sensor PCB is perforated and intended for 3.3 V
flying-wire applications. The schematic makes clear that the mini-PCB exposes
the DUT-side pads, not the same `J2` carrier interface. The same schematic
labels the mini-PCB edge pads as 0.8 x 1.6 mm. That means:

- do not connect IOT01A1 5 V to the mini-PCB;
- do not assume the carrier `J2` pinout still applies;
- explicitly provide `DUT_AVDD` and `DUT_IOVDD`; STM32 3.3 V GPIO is only a
  direct match if the sensor I/O domain is intentionally powered at 3.3 V and
  confirmed against the VL53L8 datasheet;
- add level shifting if the mini-PCB `DUT_IOVDD` domain is powered below the
  STM32 GPIO voltage;
- expect hand soldering to 0.8 x 1.6 mm edge pads.

For this project, the recommended sequence is:

1. Validate v1.2.0 with the full carrier board.
2. Design a tiny interposer/regulator board for the snap-off mini-PCB.
3. Only then break off the mini-PCB and solder the final harness.

## Recommended Harness Architecture

### Sensor End

Use a short soldered pigtail from the SATEL board into the printed case:

- 28 AWG flexible silicone wire for full-carrier board soldering;
- 30 AWG flexible silicone wire for the snap-off mini-PCB edge pads;
- heat-shrink or UV resin/epoxy strain relief over the soldered pad row;
- one locking connector just outside the case, or a connector captured by the
  case wall.

Avoid using loose Dupont sockets at the moving sensor end.

### Harness Connector

Preferred connector family: JST GH, 1.25 mm pitch, 10 positions.

Reasons:

- locking wire-to-board connector;
- common in robotics/drone harnesses;
- supports small-gauge wires;
- compact enough to mount near a small sensor case.

Molex PicoBlade 1.25 mm is also acceptable if you already have tooling or cable
assemblies. Do not mix JST GH and Molex PicoBlade parts; 1.25 mm pitch alone
does not make them mechanically compatible.

For the implemented shared-SPI two-sensor plan, use a 10-wire harness per
sensor:

| Signal | Full SATEL carrier | Rear IOT01A1 target | Front IOT01A1 target |
| --- | --- | --- | --- |
| 5V | `J2 pin 11 EXT_5V0` | shared 5V | shared 5V |
| GND | `J1 bottom` or GND | shared GND | shared GND |
| SPI/I2C mode | `J2 pin 1 EXT_SPI_I2C_N` | 3V3 for SPI | 3V3 for SPI |
| SCK | `J2 pin 6 EXT_MCLK_SCL` | D13 / PA5 | D13 / PA5 |
| MOSI | `J2 pin 5 EXT_MOSI_SDA` | D11 / PA7 | D11 / PA7 |
| MISO | `J2 pin 4 EXT_MISO` | D12 / PA6 | D12 / PA6 |
| NCS | `J2 pin 3 EXT_NCS` | D8 / PB2 | D10 / PA2 |
| LPn | `J2 pin 2 EXT_LPn` | A1 / PC4 | A0 / PC5 |
| GPIO1 | `J1 top EXT_GPIO1` | A2 / PC3 | A3 / PC2 |
| PWR_EN | `J2 pin 7 EXT_PWR_EN` | D9 / PA15 or 3V3 | 3V3 first |

For SPI cable routing, keep the shared bus tidy:

- twist or bundle SCK next to GND;
- route MISO next to GND if the cable is long;
- keep SCK/MOSI/MISO away from motor PWM wiring;
- start with 30 cm or less; test longer lengths only after SPI is stable.

For I2C fallback, twist SCL/GND and SDA/GND, keep pullups on the carrier side,
and prefer shorter cables.

### IOT01A1 End

Do not deploy with individual Dupont jumpers plugged directly into the IOT01A1.
Use one of these:

1. **Best prototype path:** Arduino R3 proto shield with stacking headers and
   two JST-GH 10-pin sensor connectors. This plugs into the IOT01A1 and gives a
   keyed harness interface.
2. **Quick path:** small solderable perfboard plugged into the IOT01A1 headers,
   with JST-GH connectors and strain relief.
3. **Final path:** custom IOT01A1 ToF adapter PCB with two keyed connectors,
   shared SPI fanout, separate `NCS`/`LPn`/`GPIO1`, and labeled test pads.

The board-side adapter should label `FRONT` and `REAR` physically. Do not rely
only on wire colors once the sensors are installed on the car.

## Cable Order List

Order these as general categories:

- 28 AWG stranded silicone wire kit, multiple colors, for full-carrier SATEL
  harnesses.
- 30 AWG stranded silicone wire or pre-bonded flexible wire for the snap-off
  mini-PCB pad soldering.
- JST-GH 10-pin housings and pre-crimped 28-30 AWG leads, or complete 10-pin
  JST-GH cable assemblies.
- JST-GH right-angle or vertical SMT/through-adapter headers for the IOT01A1
  proto shield.
- Heat-shrink tubing, 1.5-3 mm range.
- Small zip-tie anchors or adhesive cable clips for the RC car chassis.
- 3M VHB 5952 or 4910 tape for no-screw mounting trials.
- M2 screws, washers, and heat-set inserts or self-tapping plastic screws for
  repeatable mounting.

For hand assembly, pre-crimped leads are strongly preferred over crimping JST-GH
contacts manually.

## Enclosure Requirements

The enclosure should:

- hold the sensor PCB by the board edges, not by the soldered wires;
- leave a large clear aperture around the VL53L8 optical module;
- provide a rear cable exit and strain-relief channel;
- include flat underside area for VHB tape;
- include optional M2 side ears for screw mounting;
- mark front/rear orientation in the printed part or on an applied label.

The first CAD artifact is parametric OpenSCAD:

```text
firmware/stm32-mcp/hardware/cad/satel-vl53l8-mini-case/satel_vl53l8_mini_case.scad
```

OpenSCAD is not installed in the current development environment, so the model
has not been locally exported to STL. Use OpenSCAD or a slicer that can import
OpenSCAD to export:

- `part = "base"` for the tray;
- `part = "lid"` for the optical-window lid;
- `part = "assembly"` for a preview.

The default board dimensions are intentionally conservative and must be checked
with calipers after snapping off a sacrificial SATEL board. Update these
parameters first:

```text
board_w
board_h
board_t
sensor_x
sensor_y
optic_opening
```

## Printing Guidance

- Material: PETG for RC-car use; PLA is acceptable for bench fit checks.
- Layer height: 0.16-0.20 mm.
- Perimeters: 3.
- Infill: 25% or higher.
- Print base with the tape surface on the bed.
- Print lid with the outside face on the bed.
- Deburr the optical aperture; no plastic should protrude into the 65 deg
  diagonal field of view.

## Validation Checklist

1. Dry-fit the PCB without soldered wires.
2. Confirm the optical module is centered in the aperture and not shadowed.
3. Add soldered pigtail and strain relief.
4. Fit the lid without compressing components or pulling wires.
5. Mount with VHB tape on the bench and pull-test the cable lightly.
6. Verify UART VL53L8 frame logs before installing on the RC car.
7. After car installation, repeat FE63 health and iOS depth-map checks for rear
   and front roles.

## Sources

- ST SATEL-VL53L8 product page:
  <https://www.st.com/en/evaluation-tools/satel-vl53l8.html>
- ST SATEL-VL53L8 data brief:
  <https://www.st.com/resource/en/data_brief/satel-vl53l8.pdf>
- ST SATEL-VL53L8 schematic pack:
  <https://www.st.com/resource/en/schematic_pack/satel-vl53l8-schematic.pdf>
- ST AN5945:
  <https://www.st.com/resource/en/application_note/an5945-how-to-connect-the-satelvl53l8-to-an-stm32-nucleo64-board-stmicroelectronics.pdf>
- JST GH connector family:
  <https://www.jst.com/products/crimp-style-connectors-wire-to-board-type/gh-connector/>
- Molex PicoBlade connector family:
  <https://www.digikey.com/en/product-highlight/m/molex-connector/picoblade-connector-system>
- 3M VHB 5952:
  <https://www.3m.com/3M/en_US/p/dc/v100808791/>
