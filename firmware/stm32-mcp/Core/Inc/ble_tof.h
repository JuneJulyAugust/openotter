/* SPDX-License-Identifier: BSD-3-Clause */
/******************************************************************************
 * BLE GATT service for ToF debug data.
 *
 *   Service 0xFE60
 *     Char 0xFE61  Config (write-w/o-resp + write)         8 B
 *     Char 0xFE62  Frame  (notify, fixed chunks)          20 B
 *     Char 0xFE63  Status (notify + read)                  4 B
 *
 * FE61 accepts the legacy VL53L1CB config payload below, or the generic
 * Tof_Config_t V2 payload when byte 0 is TOF_SENSOR_VL53L5CX.
 * FE62 emits either legacy L1 chunks or generic V2 chunks depending on the
 * selected debug sensor.
 ******************************************************************************/
#ifndef __BLE_TOF_H
#define __BLE_TOF_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define OPENOTTER_TOF_SVC_UUID          0xFE60
#define OPENOTTER_TOF_CONFIG_CHAR_UUID  0xFE61
#define OPENOTTER_TOF_FRAME_CHAR_UUID   0xFE62
#define OPENOTTER_TOF_STATUS_CHAR_UUID  0xFE63

/* Legacy iOS -> MCU VL53L1CB configuration write payload (8 B,
 * little-endian on wire). */
typedef struct __attribute__((packed)) {
  uint8_t  layout;        /* 1, 3, 4 */
  uint8_t  dist_mode;     /* 1=SHORT, 2=MEDIUM, 3=LONG */
  uint8_t  _reserved[2];  /* must be 0 */
  uint32_t budget_us;     /* per-zone timing budget [8000..1000000] */
} BLE_TofConfigPayload_t;

_Static_assert(sizeof(BLE_TofConfigPayload_t) == 8,
               "BLE_TofConfigPayload_t must be 8 B on wire");

/* MCU -> iOS status notification (4 B). */
typedef struct __attribute__((packed)) {
  uint8_t state;         /* 0=idle, 1=running, 2=error */
  uint8_t last_error;    /* TofL1_Status_t code; 0 = none */
  uint8_t scan_hz;       /* observed scan rate, integer Hz, clamped 0..255 */
  uint8_t _pad;
} BLE_TofStatusPayload_t;

_Static_assert(sizeof(BLE_TofStatusPayload_t) == 4,
               "BLE_TofStatusPayload_t must be 4 B on wire");

/* Register service after BLE stack init (must follow BLE_App_Init). */
int  BLE_Tof_Init(void);

/* Main-loop tick: pushes frame notifications when TofL1 has a new frame and
 * the central is connected; periodically refreshes the status characteristic.
 * Suppressed in Drive mode (frame notifications reserved for Debug mode). */
void BLE_Tof_Process(void);

/* Force the ToF back to the safety-critical config (3x3 LONG 30 ms).
 * Call when the MCU transitions from Debug back to Drive mode. */
void BLE_Tof_EnforceSafetyConfig(void);

#ifdef __cplusplus
}
#endif

#endif /* __BLE_TOF_H */
