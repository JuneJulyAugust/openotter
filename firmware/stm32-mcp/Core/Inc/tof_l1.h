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
  TOF_L1_OK              = 0,
  TOF_L1_ERR_NO_SENSOR   = 1,
  TOF_L1_ERR_BOOT        = 2,
  TOF_L1_ERR_DATAINIT    = 3,
  TOF_L1_ERR_STATICINIT  = 4,
  TOF_L1_ERR_IO          = 5,
  TOF_L1_ERR_BAD_LAYOUT  = 6,
  TOF_L1_ERR_BAD_MODE    = 7,
  /* Valid layout+mode but budget below per-zone minimum or scan > 1 s. */
  TOF_L1_ERR_BAD_BUDGET  = 8,
  /* Driver error during Configure; last-known-good config was restored. */
  TOF_L1_ERR_RECOVERED   = 9,
  /* Sensor wedged and re-init failed. ToF subsystem is offline until reboot. */
  TOF_L1_ERR_DRIVER_DEAD = 10,
  /* Config write rejected because MCU is in Drive mode and the safety
   * config is locked. Sensor is still running with the safety config. */
  TOF_L1_ERR_LOCKED_IN_DRIVE = 11,
} TofL1_Status_t;

/* Minimum per-zone timing budget the driver accepts for each (layout,mode)
 * combo, in microseconds. Derived from ST UM2555 and the VL53L1CB
 * SetMeasurementTimingBudget internal guards. Exposed so the BLE layer can
 * reject bad combos with a precise error and so the iOS client can mirror
 * the firmware's clamp. Returns 0 for invalid (layout,mode) pairs. */
uint32_t TofL1_MinBudgetUs(TofL1_Layout_t layout, TofL1_DistMode_t mode);

/* Hard ceiling on total scan wall time (per-zone budget × num_zones).
 * Reasonable default — anything above this makes the refresh rate unusable. */
#define TOF_L1_MAX_SCAN_US 1000000u

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

/* 1 if the sensor is wedged and re-init failed (sticky TOF_L1_ERR_DRIVER_DEAD).
 * Cleared only by a reboot. The reverse safety supervisor treats this as a
 * permanent BRAKE condition. */
int  TofL1_IsDriverDead(void);

/* Zone rectangle in VL53L1 SPAD coordinates: X,Y in [0,15]; constraint
 * tly >= bry (sensor Y grows downward). Exposed as a plain POD so the ROI
 * builder can be unit-tested without pulling the bare driver headers. */
typedef struct {
  uint8_t tlx;
  uint8_t tly;
  uint8_t brx;
  uint8_t bry;
} TofL1_Roi_t;

/* Pure function. Fills out[] with layout*layout ROIs emitted in
 * top-to-bottom, left-to-right order (zone 0 = top-left corner) so zone
 * index maps 1:1 to iOS grid cell index. Returns the number of zones
 * written, or 0 if layout is invalid. Caller must provide capacity for
 * 16 entries. */
uint8_t TofL1_BuildRoi(TofL1_Layout_t layout, TofL1_Roi_t out[16]);

#ifdef __cplusplus
}
#endif

#endif /* TOF_L1_H */
