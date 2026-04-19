/* SPDX-License-Identifier: BSD-3-Clause */
/******************************************************************************
 * VL53L1CB wrapper — bringup skeleton (Phase B.5).
 *
 * Configure/Process are stubs; Phase B.8 fills them in. Init probes the chip
 * ID register 0x010F (expected 0xEACC) before running the bare driver boot
 * sequence so a wiring fault produces a clear UART1 log instead of a silent
 * DataInit timeout.
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
static volatile uint8_t g_has_new_frame;

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
  return TOF_L1_OK;
}

int TofL1_Configure(TofL1_Layout_t layout, TofL1_DistMode_t mode,
                    uint32_t budget_us)
{
  (void)layout;
  (void)mode;
  (void)budget_us;
  return TOF_L1_OK; /* stub — Phase B.8 */
}

void TofL1_Process(void)
{
  /* stub — Phase B.8 */
}

const TofL1_Frame_t *TofL1_GetLatestFrame(void)
{
  return &g_frame_latest;
}

int TofL1_HasNewFrame(void) { return g_has_new_frame; }

void TofL1_ClearNewFrame(void) { g_has_new_frame = 0; }
