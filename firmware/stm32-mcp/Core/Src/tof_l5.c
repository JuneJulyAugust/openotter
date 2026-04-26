/* SPDX-License-Identifier: BSD-3-Clause */
#include "tof_l5.h"
#include "tof_l5_debounce.h"

#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#include "main.h"
#include "stm32l4xx_hal.h"
#include "vl53l5cx_api.h"

extern UART_HandleTypeDef huart1;
extern I2C_HandleTypeDef hi2c3;

static Tof_Frame_t g_frame_latest;
static VL53L5CX_Configuration g_dev;
static VL53L5CX_ResultsData g_results;
static volatile uint8_t g_has_new_frame;
static uint8_t g_initialized;
static uint8_t g_streaming;
static uint8_t g_driver_dead;
static uint32_t g_seq;
static uint32_t g_last_configure_tick;

/* TOF_L5_RECONFIGURE_DEBOUNCE_MS is owned by tof_l5_debounce.h. */
#define TOF_L5_I2C_MIN_TIMEOUT_MS       1000u
#define TOF_L5_I2C_MAX_TIMEOUT_MS       15000u
static Tof_Config_t g_cfg = {
    .sensor_type = TOF_SENSOR_VL53L5CX,
    .layout = 4,
    .profile = TOF_PROFILE_L5_CONTINUOUS,
    .frequency_hz = 10,
    .integration_ms = 20,
    .budget_ms = 0,
};

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

static void stamp_empty_frame(void)
{
  memset(&g_frame_latest, 0, sizeof(g_frame_latest));
  g_frame_latest.sensor_type = TOF_SENSOR_VL53L5CX;
  g_frame_latest.layout = g_cfg.layout;
  g_frame_latest.zone_count = (uint8_t)(g_cfg.layout * g_cfg.layout);
  g_frame_latest.profile = g_cfg.profile;
  g_frame_latest.tick_ms = HAL_GetTick();
  g_has_new_frame = 0;
}

static uint8_t resolution_for_layout(uint8_t layout)
{
  return (layout == 4u) ? VL53L5CX_RESOLUTION_4X4 : VL53L5CX_RESOLUTION_8X8;
}

static uint16_t integration_for_config(const Tof_Config_t *cfg)
{
  if (cfg->integration_ms >= 2u) return cfg->integration_ms;

  uint16_t period_ms = (uint16_t)(1000u / cfg->frequency_hz);
  if (period_ms > 20u) return 20u;
  return (period_ms > 2u) ? (uint16_t)(period_ms - 1u) : 2u;
}

/* ULD downloads ~85 KB of firmware in large single-shot chunks. At 100 kHz
 * plus sensor clock-stretching, large transfers need seconds, but a cold
 * power-on bus fault must not trap the firmware forever.
 */
static uint32_t i2c_timeout_for_size(uint16_t size)
{
  uint32_t timeout = TOF_L5_I2C_MIN_TIMEOUT_MS + ((uint32_t)size / 4u);
  return (timeout > TOF_L5_I2C_MAX_TIMEOUT_MS)
             ? TOF_L5_I2C_MAX_TIMEOUT_MS
             : timeout;
}

static int32_t l5_i2c_write(uint16_t dev_addr, uint16_t reg_addr,
                            uint8_t *data, uint16_t size)
{
  HAL_StatusTypeDef s = HAL_I2C_Mem_Write(&hi2c3, dev_addr, reg_addr,
                                          I2C_MEMADD_SIZE_16BIT, data, size,
                                          i2c_timeout_for_size(size));
  return (s == HAL_OK) ? 0 : -1;
}

static int32_t l5_i2c_read(uint16_t dev_addr, uint16_t reg_addr,
                           uint8_t *data, uint16_t size)
{
  HAL_StatusTypeDef s = HAL_I2C_Mem_Read(&hi2c3, dev_addr, reg_addr,
                                         I2C_MEMADD_SIZE_16BIT, data, size,
                                         i2c_timeout_for_size(size));
  return (s == HAL_OK) ? 0 : -1;
}

static int32_t l5_get_tick(void)
{
  return (int32_t)HAL_GetTick();
}

static int stop_stream(void)
{
  if (!g_streaming) return TOF_STATUS_OK;
  uint8_t s = vl53l5cx_stop_ranging(&g_dev);
  if (s != VL53L5CX_STATUS_OK) {
    log_fmt("VL53L5 stop failed status=%u\r\n", (unsigned)s);
    g_streaming = 0;
    return TOF_STATUS_IO;
  }
  g_streaming = 0;
  return TOF_STATUS_OK;
}

static void configure_gpio(void)
{
  GPIO_InitTypeDef gpio = {0};

  gpio.Pin = ARD_A1_Pin;
  gpio.Mode = GPIO_MODE_OUTPUT_PP;
  gpio.Pull = GPIO_NOPULL;
  gpio.Speed = GPIO_SPEED_FREQ_LOW;
  HAL_GPIO_Init(ARD_A1_GPIO_Port, &gpio);

  gpio.Pin = ARD_A2_Pin;
  gpio.Mode = GPIO_MODE_INPUT;
  gpio.Pull = GPIO_NOPULL;
  gpio.Speed = GPIO_SPEED_FREQ_LOW;
  HAL_GPIO_Init(ARD_A2_GPIO_Port, &gpio);
}

static void pulse_reset(void)
{
  /* VL53L5CX I2C_RST is active high (UM2884): assert then release. Idle low. */
  HAL_GPIO_WritePin(ARD_A1_GPIO_Port, ARD_A1_Pin, GPIO_PIN_SET);
  HAL_Delay(2);
  HAL_GPIO_WritePin(ARD_A1_GPIO_Port, ARD_A1_Pin, GPIO_PIN_RESET);
  HAL_Delay(10);
}

int TofL5_Init(void)
{
  if (g_initialized) return TOF_STATUS_OK;

  log_fmt("VL53L5 init phase=gpio tick=%lu\r\n",
          (unsigned long)HAL_GetTick());
  configure_gpio();
  log_fmt("VL53L5 init phase=pulse_reset\r\n");
  pulse_reset();
  stamp_empty_frame();

  memset(&g_dev, 0, sizeof(g_dev));
  g_dev.platform.address = TOF_L5_DEFAULT_I2C_ADDR_8BIT;
  g_dev.platform.Write = l5_i2c_write;
  g_dev.platform.Read = l5_i2c_read;
  g_dev.platform.GetTick = l5_get_tick;

  /* ARD_A1 (I2C_RST) only resets the I2C interface state machine, NOT the
   * sensor's ranging engine. After an STM32 NRST while the sensor was
   * streaming, ranging continues and the next vl53l5cx_init firmware
   * download races against active ranging interrupts inside the sensor.
   * Issue a best-effort stop_ranging via the platform layer (only needs
   * g_dev.platform populated) so the firmware download lands on an idle
   * sensor. Cold boot returns an error here (sensor unconfigured) — that
   * is fine, we ignore the result. */
  log_fmt("VL53L5 init phase=stop_ranging\r\n");
  uint8_t pre_stop = vl53l5cx_stop_ranging(&g_dev);
  HAL_Delay(5);

  log_fmt("VL53L5 init phase=is_alive\r\n");
  uint8_t alive = 0;
  uint8_t s = vl53l5cx_is_alive(&g_dev, &alive);
  log_fmt("VL53L5 pre-stop=%u alive_rd=%u alive=%u tick=%lu\r\n",
          (unsigned)pre_stop, (unsigned)s, (unsigned)alive,
          (unsigned long)HAL_GetTick());
  if (s != VL53L5CX_STATUS_OK || alive == 0u) {
    log_fmt("VL53L5 probe: no sensor addr=0x%02X\r\n",
            TOF_L5_DEFAULT_I2C_ADDR_8BIT);
    return TOF_STATUS_NO_SENSOR;
  }

  log_fmt("VL53L5 init phase=fw_download tick=%lu\r\n",
          (unsigned long)HAL_GetTick());
  s = vl53l5cx_init(&g_dev);
  if (s != VL53L5CX_STATUS_OK) {
    log_fmt("VL53L5 init failed status=%u\r\n", (unsigned)s);
    return TOF_STATUS_BOOT_FAILED;
  }
  log_fmt("VL53L5 init phase=fw_done tick=%lu\r\n",
          (unsigned long)HAL_GetTick());

  g_initialized = 1u;
  int rc = TofL5_Configure(&g_cfg);
  if (rc == TOF_STATUS_OK) {
    log_fmt("VL53L5 ready L=%u Hz=%u IT=%u\r\n",
            (unsigned)g_cfg.layout, (unsigned)g_cfg.frequency_hz,
            (unsigned)g_cfg.integration_ms);
  }
  /* Release the debounce sentinel so the first external Configure call
   * (e.g. BLE_Tof_EnforceSafetyConfig raising the rate from 10 to 30 Hz on
   * Drive entry) is not silently dropped within the 500 ms window we just
   * stamped. See tof_l5_debounce.h for the contract. */
  g_last_configure_tick = 0u;
  return rc;
}

int TofL5_EnsureInitialized(void)
{
  return g_initialized ? TOF_STATUS_OK : TofL5_Init();
}

static uint8_t config_matches(const Tof_Config_t *a, const Tof_Config_t *b)
{
  return a->sensor_type   == b->sensor_type
      && a->layout        == b->layout
      && a->profile       == b->profile
      && a->frequency_hz  == b->frequency_hz
      && a->integration_ms == b->integration_ms;
}

int TofL5_Configure(const Tof_Config_t *cfg)
{
  int rc = TofL5_ValidateConfig(cfg);
  if (rc != TOF_STATUS_OK) return rc;
  if (g_driver_dead) return TOF_STATUS_DRIVER_DEAD;
  if (!g_initialized) return TOF_STATUS_NO_SENSOR;

  /* Skip if the requested config matches what is already active. */
  if (g_streaming && config_matches(cfg, &g_cfg)) {
    return TOF_STATUS_OK;
  }

  /* Debounce: reject reconfigure if the last one was < 500ms ago.
   * Rapid I2C stop/start cycles can corrupt VL53L5CX sensor state. */
  uint32_t now = HAL_GetTick();
  if (TofL5Debounce_ShouldSkip(now, g_last_configure_tick,
                               TOF_L5_RECONFIGURE_DEBOUNCE_MS)) {
    return TOF_STATUS_OK; /* silently accepted, will apply next time */
  }

  rc = stop_stream();
  if (rc != TOF_STATUS_OK) {
    return rc;
  }

  /* Small delay after stop to let the sensor settle before reconfigure. */
  HAL_Delay(2);

  uint8_t s = vl53l5cx_set_resolution(&g_dev, resolution_for_layout(cfg->layout));
  s |= vl53l5cx_set_ranging_mode(&g_dev, VL53L5CX_RANGING_MODE_AUTONOMOUS);
  s |= vl53l5cx_set_ranging_frequency_hz(&g_dev, cfg->frequency_hz);
  s |= vl53l5cx_set_integration_time_ms(&g_dev, integration_for_config(cfg));
  if (s != VL53L5CX_STATUS_OK) {
    log_fmt("VL53L5 config failed status=%u\r\n", (unsigned)s);
    return TOF_STATUS_IO;
  }

  s = vl53l5cx_start_ranging(&g_dev);
  if (s != VL53L5CX_STATUS_OK) {
    log_fmt("VL53L5 start failed status=%u\r\n", (unsigned)s);
    return TOF_STATUS_IO;
  }

  g_streaming = 1u;
  g_seq = 0;
  g_cfg = *cfg;
  g_last_configure_tick = now;
  if (g_cfg.integration_ms < 2u) {
    g_cfg.integration_ms = integration_for_config(&g_cfg);
  }
  stamp_empty_frame();
  return TOF_STATUS_OK;
}

void TofL5_Process(void)
{
  if (!g_initialized || !g_streaming) return;

  uint8_t ready = 0;
  uint8_t s = vl53l5cx_check_data_ready(&g_dev, &ready);
  if (s != VL53L5CX_STATUS_OK || ready == 0u) return;

  memset(&g_results, 0, sizeof(g_results));
  s = vl53l5cx_get_ranging_data(&g_dev, &g_results);
  if (s != VL53L5CX_STATUS_OK) return;

  g_seq++;
  g_frame_latest.sensor_type = TOF_SENSOR_VL53L5CX;
  g_frame_latest.layout = g_cfg.layout;
  g_frame_latest.zone_count = (uint8_t)(g_cfg.layout * g_cfg.layout);
  g_frame_latest.profile = g_cfg.profile;
  g_frame_latest.seq = g_seq;
  g_frame_latest.tick_ms = HAL_GetTick();

  uint8_t zones = g_frame_latest.zone_count;
  if (zones > TOF_MAX_ZONES) zones = TOF_MAX_ZONES;
  for (uint8_t i = 0; i < zones; ++i) {
    int16_t d = g_results.distance_mm[i];
    uint8_t targets = g_results.nb_target_detected[i];
    g_frame_latest.zones[i].range_mm =
        (targets == 0u || d < 0) ? 0u : (uint16_t)d;
    g_frame_latest.zones[i].status = g_results.target_status[i];
    g_frame_latest.zones[i].flags = targets;
  }
  g_has_new_frame = 1;
}

const Tof_Frame_t *TofL5_GetLatestFrame(void)
{
  return &g_frame_latest;
}

int TofL5_HasNewFrame(void) { return g_has_new_frame; }

void TofL5_ClearNewFrame(void) { g_has_new_frame = 0; }

int TofL5_IsInitialized(void) { return (int)g_initialized; }

int TofL5_IsDriverDead(void) { return (int)g_driver_dead; }
