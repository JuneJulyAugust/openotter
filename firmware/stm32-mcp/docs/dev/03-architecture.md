# 03 — Source Organization, Execution Model, and PWM

This document is the technical reference for how the firmware is
structured, how control flows through it at runtime, and how the PWM
outputs are derived from the TIM3 configuration.

Cross-references:
- Build / flash: see `01-toolchain-and-build.md`
- BLE stack & GATT flow: see `04-ble-integration.md`
- Adding sensors / new features: see `05-extending-the-firmware.md`

---

## 1. Top-level directory layout

```
firmware/stm32-mcp/
├── build.sh                  ← build + flash wrapper (toolchain doc)
├── CMakeLists.txt            ← top-level project file (user-editable stub)
├── CMakePresets.json         ← Debug / Release presets
├── cmake/
│   ├── gcc-arm-none-eabi.cmake       ← toolchain file (flags, linker)
│   ├── starm-clang.cmake             ← alt toolchain (ST-Clang, unused)
│   └── stm32cubemx/CMakeLists.txt    ← real build graph (sources, libs)
├── stm32-mcp.ioc             ← STM32CubeMX project (peripheral config)
├── STM32L475XX_FLASH.ld      ← linker script (FLASH/RAM regions)
├── startup_stm32l475xx.s     ← vector table + reset handler
├── Core/
│   ├── Inc/
│   │   ├── main.h            ← pin name #defines (generated from .ioc)
│   │   ├── ble_app.h         ← public API of the BLE application layer
│   │   ├── ble_config.h      ← BLE middleware config (scheduler, RTC, …)
│   │   ├── config.h          ← wrapper so middleware "config.h" → ble_config.h
│   │   ├── stm32l4xx_hal_conf.h
│   │   └── stm32l4xx_it.h
│   └── Src/
│       ├── main.c                 ← CubeMX init + main loop
│       ├── ble_app.c              ← custom BLE application (hand-written)
│       ├── stm32l4xx_hal_msp.c    ← peripheral pin muxing / clock enables
│       ├── stm32l4xx_it.c         ← IRQ handlers
│       ├── system_stm32l4xx.c     ← SystemInit + clock setup
│       ├── syscalls.c / sysmem.c  ← newlib stubs
├── Drivers/                  ← STM32 HAL + CMSIS (vendor, Git LFS)
├── BLE/                      ← BlueNRG-MS middleware (vendor + shims)
│   ├── ble_core/             ← ACI commands (GAP, GATT, HAL, L2CAP, HCI)
│   ├── ble_services/         ← SVCCTL dispatcher + service templates
│   ├── hw/                   ← SPI3 driver, RTC timer server, LPM hooks
│   ├── tl/                   ← HCI transport over SPI (reassembly, TX/RX)
│   ├── utilities/            ← cooperative scheduler, memory, queue, list
│   ├── debug/                ← PRINT_MESG macros (off by default)
│   ├── common.h              ← utility macros used by middleware
│   ├── config_template.h     ← reference config (not compiled)
│   ├── ble_config_template.h ← reference config (not compiled)
│   └── _reference/           ← snapshots of the STM32CubeL4 demo we forked
└── docs/                     ← datasheets, this dev documentation
```

### 1.1 "Core" vs "BLE" vs "Drivers"

| Directory  | Owner          | When to edit                                                       |
|------------|----------------|--------------------------------------------------------------------|
| `Core/`    | **Us**         | Application behavior, initialization tweaks, new features          |
| `BLE/`     | ST (imported)  | Almost never — middleware is upstream code we vendor in            |
| `Drivers/` | ST (imported)  | Never — HAL / CMSIS, Git LFS; regenerate via CubeMX if needed      |

Hand-written files are: `main.c` (user sections only), `ble_app.c`,
`ble_app.h`, `ble_config.h`, `config.h`. Everything else in `Core/` is
generated from `stm32-mcp.ioc` by STM32CubeMX and should be edited only
inside the `/* USER CODE BEGIN … END */` markers.

### 1.2 The `_reference` folder

`BLE/_reference/` contains the **verbatim** source of the STM32CubeL4
`P2P_LedButton` demo that the BLE layer was derived from. It is **not**
part of the build (see `cmake/stm32cubemx/CMakeLists.txt` — none of its
files appear in `BLE_Middleware_Src`). Keep it only as a provenance trail
and as a comparison point when the middleware behaves unexpectedly.

Original upstream location:
<https://github.com/STMicroelectronics/STM32CubeL4/tree/master/Projects/B-L475E-IOT01A/Applications/BLE/P2P_LedButton>

---

## 2. Execution model

The firmware is **single-threaded, bare-metal** — no RTOS. Concurrency
comes from three sources:

```
 ┌──────────────┐       ┌──────────────┐       ┌──────────────┐
 │  main loop   │       │  EXTI /      │       │  RTC wakeup  │
 │  (thread)    │  ◀──  │  SPI IRQ     │  ◀──  │  (timer srv) │
 └──────┬───────┘       └──────┬───────┘       └──────┬───────┘
        │                      │                      │
        ▼                      ▼                      ▼
   SCH_Run() cycles     HW_BNRG_SpiIrqCb()     HW_TS_RTC_Wakeup_Handler()
   registered tasks:    queues an HCI event    fires scheduled timers
   - HciAsynchEvt       into the reassembly    (advertising, safety
   - TlEvt              buffer                  windowing, …)
   - StartAdv
```

### 2.1 `main()` — boot sequence

Source: `Core/Src/main.c:85`.

```
HAL_Init()
    └─ sets SysTick to 1 ms, enables prefetch / ART

RCC/PWR backup-domain reset (only if pin-reset)   ← main.c:105
    └─ clears stale RTC state so HW_TS_Init won't hang

SystemClock_Config()
    └─ PLL from MSI 4 MHz → SYSCLK = 80 MHz (HCLK = 80, PCLK1/2 = 80)

MX_GPIO_Init()          ← all pins except SPI3 (owned by BLE middleware)
MX_DFSDM1_Init()        ← microphone clock, unused today
MX_I2C2_Init()          ← internal I²C bus (sensors) — bus ready, not driven
MX_QUADSPI_Init()       ← external NOR flash, unused
MX_TIM3_Init()          ← PWM channels for steering + throttle
MX_USART1/3_UART_Init() ← UART1 = ST-LINK VCP, UART3 = internal TX/RX
MX_USB_OTG_FS_PCD_Init()← USB device stack, inactive

LD1 (PA5) GPIO init     ← user code: heartbeat LED
HAL_TIM_PWM_Start(CH1)  ← start 50 Hz throttle output on PB4
HAL_TIM_PWM_Start(CH4)  ← start 50 Hz steering output on PB1
BLE_App_Init(&htim3)    ← see BLE integration doc

while (1) {
    BLE_App_Process();             ← drives the scheduler & safety timeout
    if (tick - last > 500) toggle LD1;
}
```

### 2.2 `BLE_App_Process()` — the cooperative loop

`BLE_App_Process` (in `ble_app.c:110`) is the heartbeat of the
application. Each iteration it:

1. Calls `SCH_Run()` — the `BLE/utilities/scheduler.c` cooperative
   scheduler runs every registered task whose "set" bit is pending.
   Registered tasks:
   - `CFG_IdleTask_HciAsynchEvt` → `TL_BLE_HCI_UserEvtProc()`
     (drains vendor events from the reassembly queue, dispatches to
     `SVCCTL_App_Notification` and the registered GATT handler).
   - `CFG_IdleTask_TlEvt` → `TL_BLE_R_EvtProc()` (reassembles HCI packets
     coming off SPI).
   - `CFG_IdleTask_StartAdv` → `BLE_StartAdvertising()` (deferred
     re-advertising after disconnect).
2. Checks the safety watchdog: if a central is connected and no write has
   arrived in `BLE_SAFETY_TIMEOUT_MS` (1500 ms), it forces both PWM
   channels back to neutral (1500 µs).

The IRQ handlers (in `Core/Src/stm32l4xx_it.c`) do nothing heavy — they
`SCH_SetTask(...)` to wake the relevant idle task, and return.

### 2.3 Interrupt priority map

| Source                              | Priority (pre/sub) | Handler                             |
|-------------------------------------|--------------------|-------------------------------------|
| SysTick                             | 15 / 0 (default)   | `SysTick_Handler`                   |
| RTC wake-up (timer server)          | 3 / 0              | `RTC_WKUP_IRQHandler`               |
| EXTI9_5 (SPI3 DRDY on PE6, others)  | 2 / 0              | `EXTI9_5_IRQHandler`                |
| EXTI15_10 (button, sensor DRDYs)    | 0 / 0              | `EXTI15_10_IRQHandler`              |
| USART1                              | 0x0F / 0           | `USART1_IRQHandler`                 |

RTC is intentionally slower than EXTI so BlueNRG-SPI IRQs get serviced
promptly even when a timer callback is long.

---

## 3. PWM configuration — TIM3 → steering & throttle

### 3.1 Clock arithmetic

```
SYSCLK   = 80 MHz  (PLL output, see SystemClock_Config)
APB1     = 80 MHz  (no divider → timer clock = APB1 since APB1 div = 1)
TIM3_CLK = 80 MHz

TIM3.PSC = 79        → prescaled counter clock = 80 MHz / (79+1) = 1 MHz
TIM3.ARR = 19999     → period = (19999+1) × 1 µs = 20 000 µs = 20 ms
                     → PWM frequency = 1 / 20 ms = 50 Hz   ← hobby servo std

1 timer tick = 1 µs      ⇒  CCR value in ticks == pulse width in µs.
```

This 1:1 mapping is the whole reason for choosing PSC=79. The code in
`BLE_ApplyPWM` (`ble_app.c:346`) can write µs values directly into
`CCR1` / `CCR4` via `__HAL_TIM_SET_COMPARE`.

### 3.2 Pulse-width conventions

Source constants: `Core/Inc/ble_app.h:28`.

| Macro               | Value  | Meaning                                   |
|---------------------|--------|-------------------------------------------|
| `PWM_PERIOD_US`     | 20000  | Full PWM period (50 Hz)                   |
| `PWM_NEUTRAL_US`    | 1500   | Servo center / ESC idle (stopped)         |
| `PWM_MIN_US`        | 1000   | Full reverse / full left                  |
| `PWM_MAX_US`        | 2000   | Full forward / full right                 |
| `BLE_SAFETY_TIMEOUT_MS` | 1500 | Revert to neutral after 1.5 s silence    |

`BLE_ClampPulse` (`ble_app.c:334`) enforces `[1000, 2000]` regardless of
what the iOS app sends.

### 3.3 Pin assignments for PWM

| MCU pin | Alt function        | TIM3 channel | Arduino silkscreen | Role          |
|---------|---------------------|--------------|--------------------|---------------|
| **PB1** | AF2 (`GPIO_AF2_TIM3`) | CH4          | `A6` (near ARD_A…) | Steering servo |
| **PB4** | AF2 (`GPIO_AF2_TIM3`) | CH1          | `D5` / Arduino D5  | Throttle ESC   |

Both pins are configured in `stm32l4xx_hal_msp.c` inside
`HAL_TIM_MspPostInit` (`stm32l4xx_hal_msp.c:345`):

```c
GPIO_InitStruct.Pin       = steering_pwm_Pin | throttle_pwm_Pin;  // PB1 | PB4
GPIO_InitStruct.Mode      = GPIO_MODE_AF_PP;
GPIO_InitStruct.Pull      = GPIO_NOPULL;
GPIO_InitStruct.Speed     = GPIO_SPEED_FREQ_LOW;
GPIO_InitStruct.Alternate = GPIO_AF2_TIM3;
HAL_GPIO_Init(GPIOB, &GPIO_InitStruct);
```

`steering_pwm_Pin` and `throttle_pwm_Pin` are `#define`s in `main.h`
(lines 107, 211) mapped to `GPIO_PIN_1` and `GPIO_PIN_4` respectively.

### 3.4 Boot sequence for PWM

1. `MX_TIM3_Init()` configures the counter and both output-compare
   channels in PWM1 mode with initial pulse = 1500 µs (neutral).
2. `HAL_TIM_PWM_Start(&htim3, TIM_CHANNEL_1)` and `CHANNEL_4` enable the
   CCxE bits and start the counter.
3. `BLE_App_Init` calls `BLE_ApplyPWM(PWM_NEUTRAL_US, PWM_NEUTRAL_US)`
   before advertising begins, so the outputs are at a known safe state
   before the radio is live.
4. Every subsequent BLE write updates CCR1 and CCR4 atomically.

### 3.5 Changing PWM parameters safely

- **Never** change `PSC` and `ARR` independently — pick `(PSC, ARR)` so
  that `(PSC+1)(ARR+1) = TIM3_CLK / PWM_FREQ` and `(PSC+1) = TIM3_CLK /
  1 MHz` so 1 tick still equals 1 µs.
- If you want 400 Hz ESC operation instead of 50 Hz: keep `PSC=79` (still
  1 MHz tick) and set `ARR=2499` (→ 2500 µs period). Then clamp pulses to
  `[500, 2000]`.
- The linker and startup files don't need changes for any PWM-only tweak.

---

## 4. Pin map — full board summary

The table below lists every pin that is initialized by `MX_GPIO_Init`
(`main.c:524`) with its function in this firmware. Names come from
`main.h`.

| Pin  | #define                      | Direction | Function                                 |
|------|------------------------------|-----------|------------------------------------------|
| PA5  | *(ad-hoc)*                   | Out       | **LD1** heartbeat LED (toggle every 500 ms) |
| PB1  | `steering_pwm_Pin`           | AF2       | **TIM3_CH4 — steering PWM out**          |
| PB4  | `throttle_pwm_Pin`           | AF2       | **TIM3_CH1 — throttle PWM out**          |
| PB6  | `ST_LINK_UART1_TX_Pin`       | AF7       | USART1 TX → ST-LINK VCP                  |
| PB7  | `ST_LINK_UART1_RX_Pin`       | AF7       | USART1 RX                                |
| PA8  | `SPBTLE_RF_RST_Pin`          | Out       | BlueNRG-MS reset (active low)            |
| PE6  | `SPBTLE_RF_IRQ_EXTI6_Pin`    | EXTI ↑    | BlueNRG-MS DRDY (IRQ rising)             |
| PC10 | `INTERNAL_SPI3_SCK_Pin`      | AF6       | SPI3 SCK (BlueNRG-MS, also shared bus)   |
| PC11 | `INTERNAL_SPI3_MISO_Pin`     | AF6       | SPI3 MISO                                |
| PC12 | `INTERNAL_SPI3_MOSI_Pin`     | AF6       | SPI3 MOSI                                |
| PD13 | `SPBTLE_RF_SPI3_CSN_Pin`     | Out       | SPI3 chip-select for BlueNRG-MS          |
| PB10 | `INTERNAL_I2C2_SCL_Pin`      | AF4       | I²C2 SCL (internal sensors)              |
| PB11 | `INTERNAL_I2C2_SDA_Pin`      | AF4       | I²C2 SDA                                 |
| PD11 | `LSM6DSL_INT1_EXTI11_Pin`    | EXTI ↑    | 6-axis IMU DRDY interrupt                |
| PD10 | `LPS22HB_INT_DRDY_EXTI0_Pin` | EXTI ↑    | Pressure sensor DRDY                     |
| PD15 | `HTS221_DRDY_EXTI15_Pin`     | EXTI ↑    | Humidity sensor DRDY                     |
| PC8  | `LSM3MDL_DRDY_EXTI8_Pin`     | EXTI ↑    | 3-axis magnetometer DRDY                 |
| PC6  | `VL53L0X_XSHUT_Pin`          | Out       | ToF sensor shutdown (active low)         |
| PC7  | `VL53L0X_GPIO1_EXTI7_Pin`    | EXTI ↑    | ToF sensor GPIO interrupt                |
| PC9  | `LED3_WIFI__LED4_BLE_Pin`    | Out       | WiFi/BLE combo status LED (unused today) |
| PC13 | `BUTTON_EXTI13_Pin`          | EXTI ↓    | User button B1                           |

Unused but still initialized peripherals (DFSDM1, QSPI, USB-OTG) are
present to keep the CubeMX config matching the physical board — removing
them saves a few hundred bytes of FLASH at most and is not worth the
drift from the stock `.ioc`.

### 4.1 Sensors / modules that are **not** currently driven by firmware

| Module        | Bus    | Notes                                                      |
|---------------|--------|------------------------------------------------------------|
| LSM6DSL IMU   | I²C2   | Address `0x6A` (SA0=0). See `05-extending-the-firmware.md`.|
| LIS3MDL mag.  | I²C2   | Address `0x1E`.                                            |
| LPS22HB baro. | I²C2   | Address `0x5D`.                                            |
| HTS221 humid. | I²C2   | Address `0x5F`.                                            |
| VL53L0X ToF   | I²C1 (PB8/PB9 `ARD_D15`/`D14`, AF4) | Address `0x29` (default).     |
| ISM43362 WiFi | SPI3 (shared) | Held in reset — this firmware does not use WiFi.    |
| M24SR64 NFC   | I²C (internal) | RF disabled at boot.                                  |

---

## 5. Memory layout

Linker script: `STM32L475XX_FLASH.ld`.

```
FLASH  origin 0x08000000  length 1 MiB
RAM    origin 0x20000000  length 96 KiB  (SRAM1)
RAM2   origin 0x10000000  length 32 KiB  (SRAM2, not used by default)
```

Current Debug build footprint (approximate, see `arm-none-eabi-size`
output in the build log):

| Region | Used | Total | Headroom |
|--------|------|-------|----------|
| FLASH  | ~36 KB | 1 MB | ~96%     |
| RAM    | ~4.5 KB | 96 KB | ~95%   |

There is ample room for IMU drivers, a sensor-fusion algorithm, and a
small logging buffer before needing to care about SRAM2 or QSPI flash.
