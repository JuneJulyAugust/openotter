# BLE — BlueNRG-MS Middleware

This directory is **not tracked in git**. Run `../scripts/fetch-deps.sh` to
populate it automatically, or follow the manual instructions below.

---

## Directory layout after fetch

```
BLE/
├── ble_core/       ← BlueNRG-MS ACI command builders and HCI layer
├── ble_services/   ← Generic BLE service scaffolding (from ST example)
├── hw/             ← Hardware abstraction (SPI, clock, tick)
├── tl/             ← HCI transport layer over SPI3
├── utilities/      ← osal, sequencer
├── debug/          ← Optional BLE debug utilities
└── _reference/     ← Verbatim snapshot of the upstream ST example (read-only)
```

---

## Source

Derived from the **STM32CubeL4 P2P_LedButton example** targeting the
B-L475E-IOT01A board with the SPBTLE-RF (BlueNRG-MS) module.

**Repository:** https://github.com/STMicroelectronics/STM32CubeL4  
**Example path:**
`Projects/B-L475E-IOT01A/Applications/BLE/P2P_LedButton/`

See `docs/dev/04-ble-integration.md §6` for the full provenance table mapping
each local file to its upstream counterpart.

---

## Fetch instructions

```bash
git clone --depth 1 https://github.com/STMicroelectronics/STM32CubeL4 /tmp/STM32CubeL4

EXAMPLE=/tmp/STM32CubeL4/Projects/B-L475E-IOT01A/Applications/BLE/P2P_LedButton
MIDDLEWARE=/tmp/STM32CubeL4/Middlewares/ST/BlueNRG-MS

mkdir -p BLE/{ble_core,ble_services,hw,tl,utilities,debug,_reference}

# BlueNRG-MS ACI layer
cp $MIDDLEWARE/hci/*.{c,h}                  BLE/ble_core/
cp $MIDDLEWARE/includes/*.h                 BLE/ble_core/

# Transport layer
cp $EXAMPLE/BLE_Application/TL/tl_ble_*.{c,h}  BLE/tl/

# HW abstraction, utilities, services
cp $EXAMPLE/BLE_Application/hw_*.{c,h}     BLE/hw/
cp $EXAMPLE/BLE_Application/Utilities/*.{c,h} BLE/utilities/
cp $EXAMPLE/BLE_Application/SERVICES/*.{c,h}  BLE/ble_services/

# Reference snapshot (verbatim upstream — do not edit)
cp $EXAMPLE/Core/Src/main.c                BLE/_reference/
cp $EXAMPLE/Core/Src/stm32l4xx_it.c        BLE/_reference/
cp $EXAMPLE/Core/Inc/*.h                   BLE/_reference/
```

> **Note:** The files in `BLE/` have been modified from upstream to work with
> this project's CMake build and GATT service. Do not blindly overwrite with a
> fresh clone — use the provenance table in `04-ble-integration.md` to diff
> selectively when pulling in upstream fixes.

---

## Quick check after fetch

```bash
ls BLE/ble_core/bluenrg_gatt_aci.h   # ACI layer OK
ls BLE/tl/tl_ble_io.h                # transport OK
```
