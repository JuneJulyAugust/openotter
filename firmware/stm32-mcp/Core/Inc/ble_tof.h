/* SPDX-License-Identifier: BSD-3-Clause */
/******************************************************************************
 * BLE GATT service for ToF debug data.
 *
 *   Service 0xFE60
 *     Char 0xFE61  Config (write-w/o-resp + write)         9 B
 *     Char 0xFE62  Frame  (notify, fixed chunks)          20 B
 *     Char 0xFE63  Status (notify + read)                  4 B
 *
 * FE61 accepts a VL53L8 debug config: the generic 8-byte Tof_Config_t prefix
 * plus byte 8 selecting the debug frame role (0=rear, 1=front). Deprecated
 * VL53L1/VL53L5 payloads are rejected.
 * FE62 emits generic V2 chunks.
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

typedef struct __attribute__((packed)) {
  uint8_t  sensor_type;     /* TOF_SENSOR_VL53L8CX */
  uint8_t  layout;          /* 4 or 8 for VL53L8 */
  uint8_t  profile;         /* TOF_PROFILE_L8_CONTINUOUS */
  uint8_t  frequency_hz;    /* 0 = firmware default */
  uint16_t integration_ms;  /* 0 = firmware default */
  uint16_t budget_ms;       /* reserved for VL53L8, keep 0 */
  uint8_t  debug_role;      /* 0=rear, 1=front */
} BLE_TofConfigPayload_t;

_Static_assert(sizeof(BLE_TofConfigPayload_t) == 9,
               "BLE_TofConfigPayload_t must be 9 B on wire");

/* MCU -> iOS status notification (4 B). */
typedef struct __attribute__((packed)) {
  uint8_t state;         /* 0=idle, 1=running, 2=error */
  uint8_t last_error;    /* Tof_Status_t code; 0 = none */
  uint8_t scan_hz;       /* observed scan rate, integer Hz, clamped 0..255 */
  uint8_t debug;         /* bits 0..1 selected role, bits 4..5 available mask */
} BLE_TofStatusPayload_t;

_Static_assert(sizeof(BLE_TofStatusPayload_t) == 4,
               "BLE_TofStatusPayload_t must be 4 B on wire");

/* Register service after BLE stack init (must follow BLE_App_Init). */
int  BLE_Tof_Init(void);

/* Main-loop tick: pushes frame notifications when VL53L8 has a new frame and
 * the central is connected; periodically refreshes the status characteristic.
 * Suppressed in Drive mode (frame notifications reserved for Debug mode). */
void BLE_Tof_Process(void);

/* Request the safety-critical config on the next main-loop BLE_Tof_Process.
 * Used from BLE event callbacks so VL53L8CX boot never blocks HCI handling. */
void BLE_Tof_RequestSafetyConfig(void);

/* True only after the Drive-mode VL53L8CX safety config has been applied
 * successfully. Drive throttle is held neutral until this becomes true. */
int  BLE_Tof_SafetyConfigReady(void);

/* Force the ToF back to the safety-critical config (VL53L8CX 4x4 30 Hz).
 * Call when the MCU transitions from Debug back to Drive mode. */
void BLE_Tof_EnforceSafetyConfig(void);

#ifdef __cplusplus
}
#endif

#endif /* __BLE_TOF_H */
