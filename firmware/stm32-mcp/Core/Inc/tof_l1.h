/* SPDX-License-Identifier: BSD-3-Clause */
/******************************************************************************
 * Thin wrapper over ST's VL53L1CB bare driver.
 *
 * Owns the single VL53L1_Dev_t, ROI tables, and the frame double-buffer used
 * by BLE_Tof_Process to publish grids over GATT. All public entry points are
 * main-loop-only (no ISR use).
 *
 * Frame wire format is binary-stable — the packed struct is transmitted
 * byte-for-byte over BLE notification 0xFE62 (76 B). See
 * docs/superpowers/specs/2026-04-19-vl53l1cb-multizone-tof-design.md §5.
 ******************************************************************************/
#ifndef TOF_L1_H
#define TOF_L1_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Runtime-selectable zone layouts. Numeric values are the per-side zone count
 * and are committed to the wire format. */
typedef enum {
  TOF_LAYOUT_1x1 = 1,
  TOF_LAYOUT_3x3 = 3,
  TOF_LAYOUT_4x4 = 4,
} TofL1_Layout_t;

/* Mirrors VL53L1_DistanceModes (1=SHORT/1.3 m, 2=MEDIUM/2.9 m, 3=LONG/3.6 m). */
typedef enum {
  TOF_DIST_SHORT  = 1,
  TOF_DIST_MEDIUM = 2,
  TOF_DIST_LONG   = 3,
} TofL1_DistMode_t;

typedef struct __attribute__((packed)) {
  uint16_t range_mm;  /* int16 cast → uint16; clamped to 0 on negative */
  uint8_t  status;    /* VL53L1_RangeStatus (0=OK, 2=PHA, 4=SIG, 7=WRP, 254=OOB) */
  uint8_t  _pad;
} TofL1_Zone_t;

/* 76-byte on-wire frame. Order fixed — do not reorder without bumping the
 * BLE protocol. Zone index is top-to-bottom, left-to-right (zone 0 = top-left). */
typedef struct __attribute__((packed)) {
  uint32_t seq;                 /* monotonic scan counter */
  uint16_t budget_us_per_zone;  /* echoed back from last Configure */
  uint8_t  layout;              /* 1, 3, or 4 */
  uint8_t  dist_mode;           /* 1, 2, or 3 */
  uint8_t  num_zones;           /* layout * layout */
  uint8_t  _pad[3];
  TofL1_Zone_t zones[16];
} TofL1_Frame_t;

_Static_assert(sizeof(TofL1_Frame_t) == 76, "TofL1_Frame_t must be 76 B on wire");

typedef enum {
  TOF_L1_OK             = 0,
  TOF_L1_ERR_NO_SENSOR  = 1,
  TOF_L1_ERR_BOOT       = 2,
  TOF_L1_ERR_DATAINIT   = 3,
  TOF_L1_ERR_STATICINIT = 4,
  TOF_L1_ERR_IO         = 5,
  TOF_L1_ERR_BAD_LAYOUT = 6,
  TOF_L1_ERR_BAD_MODE   = 7,
} TofL1_Status_t;

/* Boot the VL53L1CB: I²C probe → WaitDeviceBooted → DataInit → StaticInit.
 * Emits a one-shot UART1 log with the chip ID (expected 0xEACC). Safe to call
 * only once. Returns TOF_L1_OK or one of the TOF_L1_ERR_* codes. */
int TofL1_Init(void);

/* Reconfigure the preset mode, distance mode, timing budget, and ROI table.
 * Resets the frame buffers so the first post-configure frame is not stale. */
int TofL1_Configure(TofL1_Layout_t layout, TofL1_DistMode_t mode,
                    uint32_t budget_us);

/* Non-blocking — polls VL53L1_GetMeasurementDataReady once. On a complete
 * scan, swaps the scratch buffer into the latest buffer and sets
 * has_new_frame. Call once per main-loop iteration. */
void TofL1_Process(void);

/* Returns pointer to the most recently completed frame. Always valid after
 * TofL1_Init succeeds; content is zero-initialized until the first scan. */
const TofL1_Frame_t *TofL1_GetLatestFrame(void);

/* 1 if a frame has completed since the last TofL1_ClearNewFrame call. */
int  TofL1_HasNewFrame(void);
void TofL1_ClearNewFrame(void);

#ifdef __cplusplus
}
#endif

#endif /* TOF_L1_H */
