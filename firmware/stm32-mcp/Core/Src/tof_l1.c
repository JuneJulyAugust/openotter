/* SPDX-License-Identifier: BSD-3-Clause */
/******************************************************************************
 * VL53L1CB wrapper.
 *
 * Scan engine (Configure/Process):
 *   - Configure stops any in-flight ranging, sets preset/distance/budget/ROI,
 *     invalidates both frame buffers, and restarts measurement. Last-written
 *     layout/budget/mode are cached so the next frame is stamped correctly.
 *   - Process polls VL53L1_GetMeasurementDataReady once per call. On a ready
 *     reading it drains VL53L1_GetMultiRangingData, stores the zone, and on
 *     RoiStatus==VALID_LAST swaps the scratch buffer into the latest buffer
 *     and flags has_new_frame. Always calls ClearInterruptAndStartMeasurement
 *     so the sensor keeps streaming.
 *
 * HAL-only I/O path: bare driver → vl53l1_platform.c → HAL_I2C_Master_Tx/Rx
 * on hi2c3. Main-loop only (no ISR use).
 ******************************************************************************/

#include "tof_l1.h"

#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#include "stm32l4xx_hal.h"
#include "vl53l1_api.h"
#include "vl53l1_platform.h"

extern UART_HandleTypeDef huart1;

#define VL53L1_I2C_HAL_ADDR 0x52u /* 7-bit 0x29 << 1 (HAL format) */
#define VL53L1_CHIP_ID_REG  0x010Fu
#define VL53L1_CHIP_ID      0xEACCu

static VL53L1_Dev_t   g_dev;
static TofL1_Frame_t  g_frame_latest;
static TofL1_Frame_t  g_frame_scratch;
static volatile uint8_t g_has_new_frame;

/* Last committed config — restamped into every outgoing frame. */
static TofL1_Layout_t   g_cfg_layout      = TOF_LAYOUT_1x1;
static TofL1_DistMode_t g_cfg_dist_mode   = TOF_DIST_LONG;
static uint32_t         g_cfg_budget_us32 = 33000; /* source of truth */
static uint16_t         g_cfg_budget_us   = 33000; /* clamped for wire */
static uint8_t          g_cfg_num_zones   = 1;
static uint8_t          g_configured;  /* 0 until first successful Configure */
static uint8_t          g_driver_dead; /* sticky — set when recovery failed */
static uint32_t         g_seq;         /* monotonic frame counter */

/* Forward. */
static int apply_config(TofL1_Layout_t layout, TofL1_DistMode_t mode,
                        uint32_t budget_us);
static int reset_driver(void);

static void log_str(const char *s)
{
  HAL_UART_Transmit(&huart1, (const uint8_t *)s, (uint16_t)strlen(s), 100);
}

static void log_fmt(const char *fmt, ...)
{
  char buf[96];
  va_list ap;
  va_start(ap, fmt);
  int n = vsnprintf(buf, sizeof(buf), fmt, ap);
  va_end(ap);
  if (n > 0) {
    HAL_UART_Transmit(&huart1, (uint8_t *)buf, (uint16_t)n, 100);
  }
}

int TofL1_Init(void)
{
  memset(&g_dev, 0, sizeof(g_dev));
  g_dev.i2c_slave_address = VL53L1_I2C_HAL_ADDR;
  g_dev.comms_type        = 1; /* I²C */
  g_dev.comms_speed_khz   = 400;

  memset(&g_frame_latest, 0, sizeof(g_frame_latest));
  g_has_new_frame = 0;

  uint16_t id = 0;
  VL53L1_Error s = VL53L1_RdWord(&g_dev, VL53L1_CHIP_ID_REG, &id);
  log_fmt("VL53L1 probe: rd=%d id=0x%04X\r\n", (int)s, id);
  if (s != VL53L1_ERROR_NONE || id != VL53L1_CHIP_ID) {
    return TOF_L1_ERR_NO_SENSOR;
  }

  s = VL53L1_WaitDeviceBooted(&g_dev);
  if (s != VL53L1_ERROR_NONE) {
    log_fmt("VL53L1 WaitBoot err=%d\r\n", (int)s);
    return TOF_L1_ERR_BOOT;
  }

  s = VL53L1_DataInit(&g_dev);
  if (s != VL53L1_ERROR_NONE) {
    log_fmt("VL53L1 DataInit err=%d\r\n", (int)s);
    return TOF_L1_ERR_DATAINIT;
  }

  s = VL53L1_StaticInit(&g_dev);
  if (s != VL53L1_ERROR_NONE) {
    log_fmt("VL53L1 StaticInit err=%d\r\n", (int)s);
    return TOF_L1_ERR_STATICINIT;
  }

  log_str("VL53L1 ready\r\n");

  /* Start a default scan so the wrapper is usable before any BLE config
   * arrives. 1x1 / LONG / 33 ms ≈ ~30 Hz. Failures here are non-fatal —
   * the caller (BLE) can retry via TofL1_Configure later. */
  (void)TofL1_Configure(TOF_LAYOUT_1x1, TOF_DIST_LONG, 33000u);
  return TOF_L1_OK;
}

static uint8_t preset_mode_for(TofL1_Layout_t layout)
{
  return (layout == TOF_LAYOUT_1x1) ? VL53L1_PRESETMODE_RANGING
                                    : VL53L1_PRESETMODE_MULTIZONES_SCANNING;
}

static uint8_t is_valid_layout(TofL1_Layout_t layout)
{
  return layout == TOF_LAYOUT_1x1 ||
         layout == TOF_LAYOUT_3x3 ||
         layout == TOF_LAYOUT_4x4;
}

static uint8_t is_valid_mode(TofL1_DistMode_t mode)
{
  return mode == TOF_DIST_SHORT ||
         mode == TOF_DIST_MEDIUM ||
         mode == TOF_DIST_LONG;
}

static void stamp_frame_header(TofL1_Frame_t *f)
{
  f->budget_us_per_zone = g_cfg_budget_us;
  f->layout             = (uint8_t)g_cfg_layout;
  f->dist_mode          = (uint8_t)g_cfg_dist_mode;
  f->num_zones          = g_cfg_num_zones;
  f->_pad[0] = f->_pad[1] = f->_pad[2] = 0;
}

/* Per-zone minimum budget matrix. Values are what the VL53L1 driver actually
 * accepts without returning VL53L1_ERROR_INVALID_PARAMS, plus a small margin
 * taken from the ST XCubeTOF1 reference examples. Anything below these in
 * MULTIZONES mode silently wedges the FSM on some parts. */
uint32_t TofL1_MinBudgetUs(TofL1_Layout_t layout, TofL1_DistMode_t mode)
{
  if (!is_valid_layout(layout) || !is_valid_mode(mode)) return 0;

  if (layout == TOF_LAYOUT_1x1) {
    switch (mode) {
      case TOF_DIST_SHORT:  return 20000u;
      case TOF_DIST_MEDIUM: return 33000u;
      case TOF_DIST_LONG:   return 33000u;
    }
  } else {
    switch (mode) {
      case TOF_DIST_SHORT:  return  8000u;
      case TOF_DIST_MEDIUM: return 14000u;
      case TOF_DIST_LONG:   return 16000u;
    }
  }
  return 0;
}

static int validate_combo(TofL1_Layout_t layout, TofL1_DistMode_t mode,
                          uint32_t budget_us)
{
  if (!is_valid_layout(layout)) return TOF_L1_ERR_BAD_LAYOUT;
  if (!is_valid_mode(mode))     return TOF_L1_ERR_BAD_MODE;

  uint32_t min_us = TofL1_MinBudgetUs(layout, mode);
  if (min_us == 0 || budget_us < min_us) return TOF_L1_ERR_BAD_BUDGET;

  uint32_t num_zones = (uint32_t)layout * (uint32_t)layout;
  if (budget_us > TOF_L1_MAX_SCAN_US) return TOF_L1_ERR_BAD_BUDGET;
  if (budget_us * num_zones > TOF_L1_MAX_SCAN_US) return TOF_L1_ERR_BAD_BUDGET;

  return TOF_L1_OK;
}

/* Apply a pre-validated (layout,mode,budget) tuple to the sensor. No
 * validation inside — caller must have already passed validate_combo().
 * Returns TOF_L1_OK or TOF_L1_ERR_IO on any driver error. Does not restore
 * state on partial failure — callers handle recovery. */
static int apply_config(TofL1_Layout_t layout, TofL1_DistMode_t mode,
                        uint32_t budget_us)
{
  (void)VL53L1_StopMeasurement(&g_dev);

  VL53L1_Error s = VL53L1_SetPresetMode(&g_dev, preset_mode_for(layout));
  if (s != VL53L1_ERROR_NONE) { log_fmt("VL53L1 SetPreset err=%d\r\n", (int)s); return TOF_L1_ERR_IO; }

  s = VL53L1_SetDistanceMode(&g_dev, (VL53L1_DistanceModes)mode);
  if (s != VL53L1_ERROR_NONE) { log_fmt("VL53L1 SetDist err=%d\r\n", (int)s); return TOF_L1_ERR_IO; }

  s = VL53L1_SetMeasurementTimingBudgetMicroSeconds(&g_dev, budget_us);
  if (s != VL53L1_ERROR_NONE) { log_fmt("VL53L1 SetBudget err=%d\r\n", (int)s); return TOF_L1_ERR_IO; }

  if (layout != TOF_LAYOUT_1x1) {
    TofL1_Roi_t rois[16];
    uint8_t n = TofL1_BuildRoi(layout, rois);
    if (n == 0) return TOF_L1_ERR_IO;

    VL53L1_RoiConfig_t roi_cfg;
    memset(&roi_cfg, 0, sizeof(roi_cfg));
    roi_cfg.NumberOfRoi = n;
    for (uint8_t i = 0; i < n; ++i) {
      roi_cfg.UserRois[i].TopLeftX  = rois[i].tlx;
      roi_cfg.UserRois[i].TopLeftY  = rois[i].tly;
      roi_cfg.UserRois[i].BotRightX = rois[i].brx;
      roi_cfg.UserRois[i].BotRightY = rois[i].bry;
    }
    s = VL53L1_SetROI(&g_dev, &roi_cfg);
    if (s != VL53L1_ERROR_NONE) { log_fmt("VL53L1 SetROI err=%d\r\n", (int)s); return TOF_L1_ERR_IO; }
  }

  g_cfg_layout      = layout;
  g_cfg_dist_mode   = mode;
  g_cfg_budget_us32 = budget_us;
  g_cfg_budget_us   = (uint16_t)(budget_us > 65535u ? 65535u : budget_us);
  g_cfg_num_zones   = (uint8_t)((uint8_t)layout * (uint8_t)layout);

  memset(&g_frame_scratch, 0, sizeof(g_frame_scratch));
  memset(&g_frame_latest,  0, sizeof(g_frame_latest));
  stamp_frame_header(&g_frame_scratch);
  stamp_frame_header(&g_frame_latest);
  g_has_new_frame = 0;

  s = VL53L1_StartMeasurement(&g_dev);
  if (s != VL53L1_ERROR_NONE) { log_fmt("VL53L1 StartMeas err=%d\r\n", (int)s); return TOF_L1_ERR_IO; }

  g_configured = 1;
  return TOF_L1_OK;
}

/* Full sensor re-init — last resort when the driver's internal state machine
 * gets wedged by an illegal config (e.g. mid-scan mode switch failure).
 * Does not call VL53L1_Init — we never tear down the probe; DataInit +
 * StaticInit is enough to return the core algo state to boot. */
static int reset_driver(void)
{
  (void)VL53L1_StopMeasurement(&g_dev);

  VL53L1_Error s = VL53L1_DataInit(&g_dev);
  if (s != VL53L1_ERROR_NONE) {
    log_fmt("VL53L1 Reset DataInit err=%d\r\n", (int)s);
    return TOF_L1_ERR_IO;
  }
  s = VL53L1_StaticInit(&g_dev);
  if (s != VL53L1_ERROR_NONE) {
    log_fmt("VL53L1 Reset StaticInit err=%d\r\n", (int)s);
    return TOF_L1_ERR_IO;
  }
  return TOF_L1_OK;
}

int TofL1_Configure(TofL1_Layout_t layout, TofL1_DistMode_t mode,
                    uint32_t budget_us)
{
  if (g_driver_dead) return TOF_L1_ERR_DRIVER_DEAD;

  /* Reject bad combos up front — do NOT touch the sensor. The previous
   * config keeps running so a bad BLE write can't kill the ToF stream. */
  int vrc = validate_combo(layout, mode, budget_us);
  if (vrc != TOF_L1_OK) {
    log_fmt("VL53L1 reject combo L=%u M=%u B=%lu rc=%d\r\n",
            (unsigned)layout, (unsigned)mode,
            (unsigned long)budget_us, vrc);
    return vrc;
  }

  /* Snapshot last-good so we can restore if the driver rejects us. */
  TofL1_Layout_t   prev_layout = g_cfg_layout;
  TofL1_DistMode_t prev_mode   = g_cfg_dist_mode;
  uint32_t         prev_budget = g_cfg_budget_us32;
  uint8_t          had_prev    = g_configured;

  int rc = apply_config(layout, mode, budget_us);
  if (rc == TOF_L1_OK) return TOF_L1_OK;

  log_fmt("VL53L1 apply failed rc=%d — restoring previous\r\n", rc);

  if (had_prev) {
    int rrc = apply_config(prev_layout, prev_mode, prev_budget);
    if (rrc == TOF_L1_OK) return TOF_L1_ERR_RECOVERED;
    log_fmt("VL53L1 restore failed rc=%d — resetting driver\r\n", rrc);
  }

  /* Restore failed or there was no prior config — full re-init + safe default. */
  if (reset_driver() != TOF_L1_OK) {
    g_driver_dead = 1;
    g_configured  = 0;
    return TOF_L1_ERR_DRIVER_DEAD;
  }
  if (apply_config(TOF_LAYOUT_1x1, TOF_DIST_LONG, 33000u) != TOF_L1_OK) {
    g_driver_dead = 1;
    g_configured  = 0;
    return TOF_L1_ERR_DRIVER_DEAD;
  }
  return TOF_L1_ERR_RECOVERED;
}

static void ingest_zone(const VL53L1_MultiRangingData_t *raw)
{
  uint8_t idx = raw->RoiNumber;
  if (idx >= g_cfg_num_zones || idx >= 16) return;

  TofL1_Zone_t *z = &g_frame_scratch.zones[idx];

  /* Default: no object found → clamp range to 0 and use range-invalid
   * status code so downstream UI can grey the cell out. */
  uint16_t range_mm = 0;
  uint8_t  status   = VL53L1_RANGESTATUS_RANGE_INVALID;

  if (raw->NumberOfObjectsFound > 0) {
    int16_t r = raw->RangeData[0].RangeMilliMeter;
    range_mm  = (r < 0) ? 0 : (uint16_t)r;
    status    = raw->RangeData[0].RangeStatus;
  }

  z->range_mm = range_mm;
  z->status   = status;
  z->_pad     = 0;
}

void TofL1_Process(void)
{
  if (!g_configured) return;

  uint8_t ready = 0;
  VL53L1_Error s = VL53L1_GetMeasurementDataReady(&g_dev, &ready);
  if (s != VL53L1_ERROR_NONE || !ready) return;

  VL53L1_MultiRangingData_t raw;
  s = VL53L1_GetMultiRangingData(&g_dev, &raw);
  if (s != VL53L1_ERROR_NONE) {
    /* Keep sensor streaming even on a bad read. */
    (void)VL53L1_ClearInterruptAndStartMeasurement(&g_dev);
    return;
  }

  ingest_zone(&raw);

  uint8_t last_zone = (raw.RoiStatus == VL53L1_ROISTATUS_VALID_LAST) ||
                      (g_cfg_layout == TOF_LAYOUT_1x1);

  if (last_zone) {
    g_seq++;
    g_frame_scratch.seq = g_seq;
    stamp_frame_header(&g_frame_scratch);
    g_frame_latest   = g_frame_scratch;   /* publish */
    g_has_new_frame  = 1;
  }

  (void)VL53L1_ClearInterruptAndStartMeasurement(&g_dev);
}

const TofL1_Frame_t *TofL1_GetLatestFrame(void)
{
  return &g_frame_latest;
}

int TofL1_HasNewFrame(void) { return g_has_new_frame; }

void TofL1_ClearNewFrame(void) { g_has_new_frame = 0; }
