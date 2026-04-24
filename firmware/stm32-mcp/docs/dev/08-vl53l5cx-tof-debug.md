# VL53L5CX ToF Debug Bring-Up

## Hardware

X-STM32MP-MSP01 to B-L475E-IOT01A1 Arduino pins:

| IOT01A1 | MSP01 | Function |
| --- | --- | --- |
| 3V3 | pin 1 or 17, 3V3 | MSP01 logic power |
| GND | GND | Ground |
| A5 / PC0 | pin 5, SCL | I2C3 SCL |
| A4 / PC1 | pin 3, SDA | I2C3 SDA |
| A2 / PC3 | pin 35, GPIO_VL53L_INT | data-ready input |
| A1 / PC4 | pin 38, GPIO_VL53L_I2C_RST | reset output |

Do not connect IOT01A1 5V to MSP01 3V3. Use the IOT01A1 3V3 pin for the MSP01
3V3 rail.

## Firmware

The firmware keeps the existing VL53L1CB backend for reverse safety and uses
VL53L5CX as the default Debug-mode ToF stream.

Build:

```sh
cd firmware/stm32-mcp
./build.sh
```

Flash the generated `build/Debug/stm32-mcp.bin` or `.hex` as usual. On boot,
UART1 should show a VL53L5 probe line. A successful path ends with:

```text
VL53L5 ready L=4 Hz=10 IT=20
```

If the sensor is not detected, first check power: MSP01 must receive 3.3 V, not
5 V on its 3V3 pin.

## iOS Debug

Open the STM32 control screen, switch firmware to Debug mode, and use the ToF
Debug card:

- Layout: 4x4 or 8x8.
- Rate: 1 to 60 Hz for 4x4, 1 to 15 Hz for 8x8.
- Integration: 2 ms up to the frame period.

The app reassembles 20-byte FE62 chunks into the V2 frame payload and renders
the VL53L5CX grid. VL53L5CX status codes 5 and 9 are shown as OK.

Reverse safety still uses the old VL53L1CB path in Drive mode. Do not treat
VL53L5CX debug data as safety input until the later safety migration is done.
