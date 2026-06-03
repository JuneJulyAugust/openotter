/* SPDX-License-Identifier: BSD-3-Clause */
#include "tof_l8.h"
#include "tof_l8_debounce.h"

#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#include "main.h"
#include "stm32l4xx_hal.h"
#include "firmware_watchdog.h"
#include "tof_l8_transport.h"
#include "tof_l8_status.h"
#include "vl53l8cx_api.h"

extern UART_HandleTypeDef huart1;

static Tof_Frame_t g_frame_latest;
static VL53L8CX_Configuration g_dev;
static VL53L8CX_ResultsData g_results;
static TofL8TransportHandle_t g_transport;
static volatile uint8_t g_has_new_frame;
static uint8_t g_initialized;
static uint8_t g_streaming;
static uint8_t g_driver_dead;
static uint32_t g_seq;
static uint32_t g_last_configure_tick;
static uint32_t g_last_frame_log_tick;
static uint32_t g_last_frame_log_seq;

/* TOF_L8_RECONFIGURE_DEBOUNCE_MS is owned by tof_l8_debounce.h. */
#define TOF_L8_FRAME_LOG_INTERVAL_MS    1000u
static Tof_Config_t g_cfg = {
    .sensor_type = TOF_SENSOR_VL53L8CX,
    .layout = 4,
    .profile = TOF_PROFILE_L8_CONTINUOUS,
    .frequency_hz = 10,
    .integration_ms = 20,
    .budget_ms = 0,
};

static void log_prefix(void)
{
  char buf[16];
  int n = snprintf(buf, sizeof(buf), "[%lu] ",
                   (unsigned long)HAL_GetTick());
  if (n > 0) {
    HAL_UART_Transmit(&huart1, (uint8_t *)buf, (uint16_t)n, 100);
  }
}

static void log_fmt(const char *fmt, ...)
{
  char buf[256];
  va_list ap;
  va_start(ap, fmt);
  int n = vsnprintf(buf, sizeof(buf), fmt, ap);
  va_end(ap);
  if (n > 0) {
    if ((size_t)n >= sizeof(buf)) {
      n = (int)sizeof(buf) - 1;
    }
    log_prefix();
    HAL_UART_Transmit(&huart1, (uint8_t *)buf, (uint16_t)n, 100);
  }
}

static uint16_t logged_range_at(uint8_t idx)
{
  return (idx < g_frame_latest.zone_count) ? g_frame_latest.zones[idx].range_mm
                                           : 0u;
}

static uint8_t logged_status_at(uint8_t idx)
{
  return (idx < g_frame_latest.zone_count) ? g_frame_latest.zones[idx].status
                                           : 0u;
}

static uint8_t logged_flags_at(uint8_t idx)
{
  return (idx < g_frame_latest.zone_count) ? g_frame_latest.zones[idx].flags
                                           : 0u;
}

static void append_grid_text(char *buf, size_t len, size_t *off,
                             const char *fmt, ...)
{
  if (*off >= len) return;

  va_list ap;
  va_start(ap, fmt);
  int n = vsnprintf(&buf[*off], len - *off, fmt, ap);
  va_end(ap);
  if (n <= 0) return;

  size_t wrote = (size_t)n;
  *off += (wrote >= (len - *off)) ? (len - *off - 1u) : wrote;
}

static void log_4x4_grid(void)
{
  if (g_frame_latest.layout != 4u || g_frame_latest.zone_count < 16u) return;

  char buf[256];
  size_t off = 0u;
  append_grid_text(buf, sizeof(buf), &off, "VL53L8 grid r/s/f: ");
  for (uint8_t row = 0u; row < 4u; ++row) {
    if (row > 0u) {
      append_grid_text(buf, sizeof(buf), &off, " | ");
    }
    for (uint8_t col = 0u; col < 4u; ++col) {
      uint8_t idx = (uint8_t)(row * 4u + col);
      append_grid_text(buf, sizeof(buf), &off, "%u/%u/%u%s",
                       (unsigned)logged_range_at(idx),
                       (unsigned)logged_status_at(idx),
                       (unsigned)logged_flags_at(idx),
                       (col == 3u) ? "" : " ");
    }
  }
  append_grid_text(buf, sizeof(buf), &off, "\r\n");
  if (off > 0u) {
    log_prefix();
    HAL_UART_Transmit(&huart1, (uint8_t *)buf, (uint16_t)off, 100);
  }
}

static void stamp_empty_frame(void)
{
  memset(&g_frame_latest, 0, sizeof(g_frame_latest));
  g_frame_latest.sensor_type = TOF_SENSOR_VL53L8CX;
  g_frame_latest.layout = g_cfg.layout;
  g_frame_latest.zone_count = (uint8_t)(g_cfg.layout * g_cfg.layout);
  g_frame_latest.profile = g_cfg.profile;
  g_frame_latest.tick_ms = HAL_GetTick();
  g_has_new_frame = 0;
}

static uint8_t resolution_for_layout(uint8_t layout)
{
  return (layout == 4u) ? VL53L8CX_RESOLUTION_4X4 : VL53L8CX_RESOLUTION_8X8;
}

static uint16_t integration_for_config(const Tof_Config_t *cfg)
{
  if (cfg->integration_ms >= 2u) return cfg->integration_ms;

  uint16_t period_ms = (uint16_t)(1000u / cfg->frequency_hz);
  if (period_ms > 20u) return 20u;
  return (period_ms > 2u) ? (uint16_t)(period_ms - 1u) : 2u;
}

static const char *transport_name(TofL8TransportKind_t kind)
{
  if (kind == TOF_L8_TRANSPORT_I2C) return "i2c3";
  if (kind == TOF_L8_TRANSPORT_SPI) return "spi1";
  if (kind == TOF_L8_TRANSPORT_AMBIGUOUS) return "ambiguous";
  return "none";
}

static void apply_transport(TofL8TransportHandle_t *transport)
{
  g_dev.platform.address = (transport->kind == TOF_L8_TRANSPORT_I2C)
                               ? transport->i2c.addr_8bit
                               : 0u;
  g_dev.platform.Write = TofL8Transport_Write;
  g_dev.platform.Read = TofL8Transport_Read;
  g_dev.platform.Wait = TofL8Transport_Wait;
  g_dev.platform.handle = transport;
}

typedef struct {
  TofL8TransportHandle_t transport;
  uint8_t pre_stop;
  uint8_t alive_read;
  uint8_t alive;
} TofL8ProbeResult_t;

static void probe_transport(const TofL8TransportHandle_t *candidate,
                            TofL8ProbeResult_t *result)
{
  memset(result, 0, sizeof(*result));
  result->transport = *candidate;
  memset(&g_dev, 0, sizeof(g_dev));
  apply_transport(&result->transport);

  log_fmt("VL53L8 probe transport=%s phase=stop_ranging\r\n",
          transport_name(result->transport.kind));
  result->pre_stop = vl53l8cx_stop_ranging(&g_dev);
  HAL_Delay(5);

  log_fmt("VL53L8 probe transport=%s phase=is_alive\r\n",
          transport_name(result->transport.kind));
  result->alive_read = vl53l8cx_is_alive(&g_dev, &result->alive);
  log_fmt("VL53L8 probe transport=%s pre_stop=%u alive_rd=%u alive=%u tick=%lu\r\n",
          transport_name(result->transport.kind), (unsigned)result->pre_stop,
          (unsigned)result->alive_read, (unsigned)result->alive,
          (unsigned long)HAL_GetTick());
}

static int stop_stream(void)
{
  if (!g_streaming) return TOF_STATUS_OK;
  uint8_t s = vl53l8cx_stop_ranging(&g_dev);
  if (s != VL53L8CX_STATUS_OK) {
    log_fmt("VL53L8 stop failed status=%u\r\n", (unsigned)s);
    g_streaming = 0;
    return TOF_STATUS_IO;
  }
  g_streaming = 0;
  return TOF_STATUS_OK;
}

static void configure_gpio(void)
{
  GPIO_InitTypeDef gpio = {0};

  gpio.Pin = ARD_D8_Pin;
  gpio.Mode = GPIO_MODE_OUTPUT_PP;
  gpio.Pull = GPIO_NOPULL;
  gpio.Speed = GPIO_SPEED_FREQ_LOW;
  HAL_GPIO_Init(ARD_D8_GPIO_Port, &gpio);
  HAL_GPIO_WritePin(ARD_D8_GPIO_Port, ARD_D8_Pin, GPIO_PIN_SET);

  gpio.Pin = ARD_D10_Pin;
  gpio.Mode = GPIO_MODE_OUTPUT_PP;
  gpio.Pull = GPIO_NOPULL;
  gpio.Speed = GPIO_SPEED_FREQ_LOW;
  HAL_GPIO_Init(ARD_D10_GPIO_Port, &gpio);
  HAL_GPIO_WritePin(ARD_D10_GPIO_Port, ARD_D10_Pin, GPIO_PIN_SET);

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
  /* SATEL VL53L8 LPn is active low: hold low, then release high. */
  HAL_GPIO_WritePin(ARD_A1_GPIO_Port, ARD_A1_Pin, GPIO_PIN_RESET);
  HAL_Delay(2);
  HAL_GPIO_WritePin(ARD_A1_GPIO_Port, ARD_A1_Pin, GPIO_PIN_SET);
  HAL_Delay(10);
}

int TofL8_Init(void)
{
  if (g_initialized) return TOF_STATUS_OK;

  log_fmt("VL53L8 init phase=gpio tick=%lu\r\n",
          (unsigned long)HAL_GetTick());
  configure_gpio();
  log_fmt("VL53L8 init phase=pulse_reset\r\n");
  pulse_reset();
  stamp_empty_frame();

  TofL8ProbeResult_t i2c_probe;
  TofL8ProbeResult_t spi_probe;
  TofL8TransportHandle_t candidate;

  TofL8Transport_InitI2c(&candidate, TOF_L8_I2C_BUS_3,
                         TOF_L8_DEFAULT_I2C_ADDR_8BIT);
  probe_transport(&candidate, &i2c_probe);

  TofL8Transport_InitSpi(&candidate, TOF_L8_SPI_BUS_1, TOF_L8_GPIO_PB2_D8);
  probe_transport(&candidate, &spi_probe);

  int i2c_alive = (i2c_probe.alive_read == VL53L8CX_STATUS_OK &&
                   i2c_probe.alive != 0u);
  int spi_alive = (spi_probe.alive_read == VL53L8CX_STATUS_OK &&
                   spi_probe.alive != 0u);
  TofL8TransportKind_t selected =
      TofL8Transport_ChooseProbe(i2c_alive, spi_alive);
  if (selected == TOF_L8_TRANSPORT_NONE) {
    log_fmt("VL53L8 probe: no sensor i2c_rd=%u i2c_alive=%u "
            "spi_rd=%u spi_alive=%u\r\n",
            (unsigned)i2c_probe.alive_read, (unsigned)i2c_probe.alive,
            (unsigned)spi_probe.alive_read, (unsigned)spi_probe.alive);
    return TOF_STATUS_NO_SENSOR;
  }
  if (selected == TOF_L8_TRANSPORT_AMBIGUOUS) {
    log_fmt("VL53L8 probe: ambiguous transport i2c_alive=%u spi_alive=%u\r\n",
            (unsigned)i2c_probe.alive, (unsigned)spi_probe.alive);
    return TOF_STATUS_IO;
  }

  g_transport = (selected == TOF_L8_TRANSPORT_I2C)
                    ? i2c_probe.transport
                    : spi_probe.transport;
  memset(&g_dev, 0, sizeof(g_dev));
  apply_transport(&g_transport);
  log_fmt("VL53L8 selected transport=%s\r\n", transport_name(selected));

  log_fmt("VL53L8 init phase=fw_download tick=%lu\r\n",
          (unsigned long)HAL_GetTick());
  uint8_t s = vl53l8cx_init(&g_dev);
  if (s != VL53L8CX_STATUS_OK) {
    log_fmt("VL53L8 init failed status=%u\r\n", (unsigned)s);
    return TOF_STATUS_BOOT_FAILED;
  }
  log_fmt("VL53L8 init phase=fw_done tick=%lu\r\n",
          (unsigned long)HAL_GetTick());

  g_initialized = 1u;
  int rc = TofL8_Configure(&g_cfg);
  if (rc == TOF_STATUS_OK) {
    log_fmt("VL53L8 ready L=%u Hz=%u IT=%u\r\n",
            (unsigned)g_cfg.layout, (unsigned)g_cfg.frequency_hz,
            (unsigned)g_cfg.integration_ms);
  }
  /* Release the debounce sentinel so the first external Configure call
   * (e.g. BLE_Tof_EnforceSafetyConfig raising the rate from 10 to 30 Hz on
   * Drive entry) is not silently dropped within the 500 ms window we just
   * stamped. See tof_l8_debounce.h for the contract. */
  g_last_configure_tick = 0u;
  return rc;
}

int TofL8_EnsureInitialized(void)
{
  return g_initialized ? TOF_STATUS_OK : TofL8_Init();
}

static uint8_t config_matches(const Tof_Config_t *a, const Tof_Config_t *b)
{
  return a->sensor_type   == b->sensor_type
      && a->layout        == b->layout
      && a->profile       == b->profile
      && a->frequency_hz  == b->frequency_hz
      && a->integration_ms == b->integration_ms;
}

int TofL8_Configure(const Tof_Config_t *cfg)
{
  int rc = TofL8_ValidateConfig(cfg);
  if (rc != TOF_STATUS_OK) return rc;
  if (g_driver_dead) return TOF_STATUS_DRIVER_DEAD;
  if (!g_initialized) return TOF_STATUS_NO_SENSOR;

  /* Skip if the requested config matches what is already active. */
  if (g_streaming && config_matches(cfg, &g_cfg)) {
    return TOF_STATUS_OK;
  }

  /* Debounce: reject reconfigure if the last one was < 500ms ago.
   * Rapid I2C stop/start cycles can corrupt VL53L8CX sensor state. */
  uint32_t now = HAL_GetTick();
  if (TofL8Debounce_ShouldSkip(now, g_last_configure_tick,
                               TOF_L8_RECONFIGURE_DEBOUNCE_MS)) {
    return TOF_STATUS_OK; /* silently accepted, will apply next time */
  }

  rc = stop_stream();
  if (rc != TOF_STATUS_OK) {
    return rc;
  }

  /* Small delay after stop to let the sensor settle before reconfigure. */
  HAL_Delay(2);

  uint8_t s = vl53l8cx_set_resolution(&g_dev, resolution_for_layout(cfg->layout));
  s |= vl53l8cx_set_ranging_mode(&g_dev, VL53L8CX_RANGING_MODE_AUTONOMOUS);
  s |= vl53l8cx_set_ranging_frequency_hz(&g_dev, cfg->frequency_hz);
  s |= vl53l8cx_set_integration_time_ms(&g_dev, integration_for_config(cfg));
  if (s != VL53L8CX_STATUS_OK) {
    log_fmt("VL53L8 config failed status=%u\r\n", (unsigned)s);
    return TOF_STATUS_IO;
  }

  s = vl53l8cx_start_ranging(&g_dev);
  if (s != VL53L8CX_STATUS_OK) {
    log_fmt("VL53L8 start failed status=%u\r\n", (unsigned)s);
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
  g_last_frame_log_tick = 0u;
  g_last_frame_log_seq = 0u;
  log_fmt("VL53L8 stream start layout=%u zones=%u hz=%u it=%u readBytes=%lu\r\n",
          (unsigned)g_cfg.layout, (unsigned)g_frame_latest.zone_count,
          (unsigned)g_cfg.frequency_hz, (unsigned)g_cfg.integration_ms,
          (unsigned long)g_dev.data_read_size);
  return TOF_STATUS_OK;
}

void TofL8_Process(void)
{
  if (!g_initialized || !g_streaming) return;

  uint8_t ready = 0;
  uint8_t s = vl53l8cx_check_data_ready(&g_dev, &ready);
  if (s != VL53L8CX_STATUS_OK || ready == 0u) return;

  memset(&g_results, 0, sizeof(g_results));
  s = vl53l8cx_get_ranging_data(&g_dev, &g_results);
  if (s != VL53L8CX_STATUS_OK) return;

  g_seq++;
  g_frame_latest.sensor_type = TOF_SENSOR_VL53L8CX;
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

  uint32_t now = g_frame_latest.tick_ms;
  if (g_seq == 1u ||
      (now - g_last_frame_log_tick) >= TOF_L8_FRAME_LOG_INTERVAL_MS) {
    uint8_t layout = g_frame_latest.layout;
    uint8_t last = (zones > 0u) ? (uint8_t)(zones - 1u) : 0u;
    uint8_t c0 = (layout > 1u) ? (uint8_t)((layout / 2u) - 1u) : 0u;
    uint8_t c1 = (layout > 1u) ? (uint8_t)(layout / 2u) : 0u;
    uint8_t cc00 = (uint8_t)(c0 * layout + c0);
    uint8_t cc01 = (uint8_t)(c0 * layout + c1);
    uint8_t cc10 = (uint8_t)(c1 * layout + c0);
    uint8_t cc11 = (uint8_t)(c1 * layout + c1);
    uint8_t target_zones = 0u;
    uint16_t min_mm = UINT16_MAX;
    uint16_t max_mm = 0u;
    for (uint8_t i = 0u; i < zones; ++i) {
      uint16_t range_mm = g_frame_latest.zones[i].range_mm;
      if (g_frame_latest.zones[i].flags > 0u && range_mm > 0u &&
          TofL8_StatusIsRangeValid(g_frame_latest.zones[i].status)) {
        target_zones++;
        if (range_mm < min_mm) min_mm = range_mm;
        if (range_mm > max_mm) max_mm = range_mm;
      }
    }
    if (target_zones == 0u) {
      min_mm = 0u;
    }
    uint32_t frame_delta = (g_last_frame_log_seq == 0u)
                               ? g_seq
                               : (g_seq - g_last_frame_log_seq);
    g_last_frame_log_tick = now;
    g_last_frame_log_seq = g_seq;
    log_fmt("VL53L8 frame layout=%u zones=%u seq=%lu fps=%lu targetZones=%u "
            "min=%u max=%u z0=%u/%u/%u zLast=%u/%u/%u "
            "center=%u,%u,%u,%u cst=%u,%u,%u,%u cn=%u,%u,%u,%u\r\n",
            (unsigned)layout, (unsigned)zones, (unsigned long)g_seq,
            (unsigned long)frame_delta, (unsigned)target_zones,
            (unsigned)min_mm, (unsigned)max_mm,
            (unsigned)logged_range_at(0u),
            (unsigned)logged_status_at(0u),
            (unsigned)logged_flags_at(0u),
            (unsigned)logged_range_at(last),
            (unsigned)logged_status_at(last),
            (unsigned)logged_flags_at(last),
            (unsigned)logged_range_at(cc00), (unsigned)logged_range_at(cc01),
            (unsigned)logged_range_at(cc10), (unsigned)logged_range_at(cc11),
            (unsigned)logged_status_at(cc00), (unsigned)logged_status_at(cc01),
            (unsigned)logged_status_at(cc10), (unsigned)logged_status_at(cc11),
            (unsigned)logged_flags_at(cc00), (unsigned)logged_flags_at(cc01),
            (unsigned)logged_flags_at(cc10), (unsigned)logged_flags_at(cc11));
    log_4x4_grid();
  }
}

const Tof_Frame_t *TofL8_GetLatestFrame(void)
{
  return &g_frame_latest;
}

int TofL8_HasNewFrame(void) { return g_has_new_frame; }

void TofL8_ClearNewFrame(void) { g_has_new_frame = 0; }

int TofL8_IsInitialized(void) { return (int)g_initialized; }

int TofL8_IsDriverDead(void) { return (int)g_driver_dead; }
