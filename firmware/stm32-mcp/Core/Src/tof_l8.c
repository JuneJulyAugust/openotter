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

typedef struct {
  Tof_Frame_t frame_latest;
  VL53L8CX_Configuration dev;
  VL53L8CX_ResultsData results;
  TofL8TransportHandle_t transport;
  uint8_t initialized;
  uint8_t streaming;
  uint8_t driver_dead;
  volatile uint8_t has_new_frame;
  uint32_t seq;
  uint32_t last_frame_log_tick;
  uint32_t last_frame_log_seq;
} TofL8SlotRuntime_t;

typedef struct {
  TofL8TransportHandle_t transport;
  uint8_t pre_stop;
  uint8_t alive_read;
  uint8_t alive;
} TofL8ProbeResult_t;

static TofL8SlotRuntime_t g_slots[TOF_L8_SENSOR_COUNT];
static uint8_t g_initialized;
static uint32_t g_last_configure_tick;

/* TOF_L8_RECONFIGURE_DEBOUNCE_MS is owned by tof_l8_debounce.h. */
#define TOF_L8_FRAME_LOG_INTERVAL_MS 1000u

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

static const char *sensor_name(TofL8SensorId_t sensor_id)
{
  return (sensor_id == TOF_L8_SENSOR_FRONT) ? "front" : "rear";
}

static const char *transport_name(TofL8TransportKind_t kind)
{
  if (kind == TOF_L8_TRANSPORT_I2C) return "i2c3";
  if (kind == TOF_L8_TRANSPORT_SPI) return "spi1";
  if (kind == TOF_L8_TRANSPORT_AMBIGUOUS) return "ambiguous";
  return "none";
}

static TofL8SlotRuntime_t *slot_for(TofL8SensorId_t sensor_id)
{
  if ((uint8_t)sensor_id >= (uint8_t)TOF_L8_SENSOR_COUNT) return 0;
  return &g_slots[(uint8_t)sensor_id];
}

static TofL8SlotRuntime_t *default_slot(void)
{
  if (TofL8_IsSensorAvailable(TOF_L8_SENSOR_REAR)) {
    return slot_for(TOF_L8_SENSOR_REAR);
  }
  if (TofL8_IsSensorAvailable(TOF_L8_SENSOR_FRONT)) {
    return slot_for(TOF_L8_SENSOR_FRONT);
  }
  return slot_for(TOF_L8_SENSOR_REAR);
}

static uint16_t logged_range_at(const TofL8SlotRuntime_t *slot, uint8_t idx)
{
  return (slot && idx < slot->frame_latest.zone_count)
             ? slot->frame_latest.zones[idx].range_mm
             : 0u;
}

static uint8_t logged_status_at(const TofL8SlotRuntime_t *slot, uint8_t idx)
{
  return (slot && idx < slot->frame_latest.zone_count)
             ? slot->frame_latest.zones[idx].status
             : 0u;
}

static uint8_t logged_flags_at(const TofL8SlotRuntime_t *slot, uint8_t idx)
{
  return (slot && idx < slot->frame_latest.zone_count)
             ? slot->frame_latest.zones[idx].flags
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

static void log_4x4_grid(TofL8SensorId_t sensor_id,
                         const TofL8SlotRuntime_t *slot)
{
  if (!slot ||
      slot->frame_latest.layout != 4u ||
      slot->frame_latest.zone_count < 16u) {
    return;
  }

  char buf[256];
  size_t off = 0u;
  append_grid_text(buf, sizeof(buf), &off, "VL53L8 %s grid r/s/f: ",
                   sensor_name(sensor_id));
  for (uint8_t row = 0u; row < 4u; ++row) {
    if (row > 0u) {
      append_grid_text(buf, sizeof(buf), &off, " | ");
    }
    for (uint8_t col = 0u; col < 4u; ++col) {
      uint8_t idx = (uint8_t)(row * 4u + col);
      append_grid_text(buf, sizeof(buf), &off, "%u/%u/%u%s",
                       (unsigned)logged_range_at(slot, idx),
                       (unsigned)logged_status_at(slot, idx),
                       (unsigned)logged_flags_at(slot, idx),
                       (col == 3u) ? "" : " ");
    }
  }
  append_grid_text(buf, sizeof(buf), &off, "\r\n");
  if (off > 0u) {
    log_prefix();
    HAL_UART_Transmit(&huart1, (uint8_t *)buf, (uint16_t)off, 100);
  }
}

static void stamp_empty_frame(TofL8SlotRuntime_t *slot)
{
  if (!slot) return;
  memset(&slot->frame_latest, 0, sizeof(slot->frame_latest));
  slot->frame_latest.sensor_type = TOF_SENSOR_VL53L8CX;
  slot->frame_latest.layout = g_cfg.layout;
  slot->frame_latest.zone_count = (uint8_t)(g_cfg.layout * g_cfg.layout);
  slot->frame_latest.profile = g_cfg.profile;
  slot->frame_latest.tick_ms = HAL_GetTick();
  slot->has_new_frame = 0;
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

static void apply_transport(VL53L8CX_Configuration *dev,
                            TofL8TransportHandle_t *transport)
{
  dev->platform.address = (transport->kind == TOF_L8_TRANSPORT_I2C)
                              ? transport->i2c.addr_8bit
                              : 0u;
  dev->platform.Write = TofL8Transport_Write;
  dev->platform.Read = TofL8Transport_Read;
  dev->platform.Wait = TofL8Transport_Wait;
  dev->platform.handle = transport;
}

static void probe_transport(TofL8SensorId_t sensor_id,
                            TofL8SlotRuntime_t *slot,
                            const TofL8TransportHandle_t *candidate,
                            TofL8ProbeResult_t *result)
{
  memset(result, 0, sizeof(*result));
  result->transport = *candidate;
  memset(&slot->dev, 0, sizeof(slot->dev));
  apply_transport(&slot->dev, &result->transport);

  log_fmt("VL53L8 %s probe transport=%s phase=stop_ranging\r\n",
          sensor_name(sensor_id), transport_name(result->transport.kind));
  result->pre_stop = vl53l8cx_stop_ranging(&slot->dev);
  HAL_Delay(5);

  log_fmt("VL53L8 %s probe transport=%s phase=is_alive\r\n",
          sensor_name(sensor_id), transport_name(result->transport.kind));
  result->alive_read = vl53l8cx_is_alive(&slot->dev, &result->alive);
  log_fmt("VL53L8 %s probe transport=%s pre_stop=%u alive_rd=%u "
          "alive=%u tick=%lu\r\n",
          sensor_name(sensor_id), transport_name(result->transport.kind),
          (unsigned)result->pre_stop, (unsigned)result->alive_read,
          (unsigned)result->alive, (unsigned long)HAL_GetTick());
}

static int probe_alive(const TofL8ProbeResult_t *probe)
{
  return probe->alive_read == VL53L8CX_STATUS_OK && probe->alive != 0u;
}

static int stop_stream(TofL8SensorId_t sensor_id, TofL8SlotRuntime_t *slot)
{
  if (!slot || !slot->streaming) return TOF_STATUS_OK;
  uint8_t s = vl53l8cx_stop_ranging(&slot->dev);
  if (s != VL53L8CX_STATUS_OK) {
    log_fmt("VL53L8 %s stop failed status=%u\r\n",
            sensor_name(sensor_id), (unsigned)s);
    slot->streaming = 0;
    slot->driver_dead = 1u;
    return TOF_STATUS_IO;
  }
  slot->streaming = 0;
  return TOF_STATUS_OK;
}

static void configure_gpio(void)
{
  GPIO_InitTypeDef gpio = {0};

  gpio.Mode = GPIO_MODE_OUTPUT_PP;
  gpio.Pull = GPIO_NOPULL;
  gpio.Speed = GPIO_SPEED_FREQ_LOW;

  gpio.Pin = ARD_D8_Pin;
  HAL_GPIO_Init(ARD_D8_GPIO_Port, &gpio);
  HAL_GPIO_WritePin(ARD_D8_GPIO_Port, ARD_D8_Pin, GPIO_PIN_SET);

  gpio.Pin = ARD_D10_Pin;
  HAL_GPIO_Init(ARD_D10_GPIO_Port, &gpio);
  HAL_GPIO_WritePin(ARD_D10_GPIO_Port, ARD_D10_Pin, GPIO_PIN_SET);

  gpio.Pin = ARD_A1_Pin;
  HAL_GPIO_Init(ARD_A1_GPIO_Port, &gpio);
  HAL_GPIO_WritePin(ARD_A1_GPIO_Port, ARD_A1_Pin, GPIO_PIN_RESET);

  gpio.Pin = ARD_A0_Pin;
  HAL_GPIO_Init(ARD_A0_GPIO_Port, &gpio);
  HAL_GPIO_WritePin(ARD_A0_GPIO_Port, ARD_A0_Pin, GPIO_PIN_RESET);

  gpio.Mode = GPIO_MODE_INPUT;
  gpio.Pin = ARD_A2_Pin;
  HAL_GPIO_Init(ARD_A2_GPIO_Port, &gpio);

  gpio.Pin = ARD_A3_Pin;
  HAL_GPIO_Init(ARD_A3_GPIO_Port, &gpio);
}

static void pulse_reset(TofL8SensorId_t sensor_id)
{
  GPIO_TypeDef *port = (sensor_id == TOF_L8_SENSOR_FRONT)
                           ? ARD_A0_GPIO_Port
                           : ARD_A1_GPIO_Port;
  uint16_t pin = (sensor_id == TOF_L8_SENSOR_FRONT) ? ARD_A0_Pin : ARD_A1_Pin;

  HAL_GPIO_WritePin(port, pin, GPIO_PIN_RESET);
  HAL_Delay(2);
  HAL_GPIO_WritePin(port, pin, GPIO_PIN_SET);
  HAL_Delay(10);
}

static int init_slot_from_probe(TofL8SensorId_t sensor_id,
                                TofL8SlotRuntime_t *slot,
                                const TofL8ProbeResult_t *probe)
{
  slot->transport = probe->transport;
  memset(&slot->dev, 0, sizeof(slot->dev));
  apply_transport(&slot->dev, &slot->transport);
  log_fmt("VL53L8 %s selected transport=%s\r\n",
          sensor_name(sensor_id), transport_name(slot->transport.kind));

  log_fmt("VL53L8 %s init phase=fw_download tick=%lu\r\n",
          sensor_name(sensor_id), (unsigned long)HAL_GetTick());
  uint8_t s = vl53l8cx_init(&slot->dev);
  if (s != VL53L8CX_STATUS_OK) {
    log_fmt("VL53L8 %s init failed status=%u\r\n",
            sensor_name(sensor_id), (unsigned)s);
    slot->driver_dead = 1u;
    return TOF_STATUS_BOOT_FAILED;
  }
  log_fmt("VL53L8 %s init phase=fw_done tick=%lu\r\n",
          sensor_name(sensor_id), (unsigned long)HAL_GetTick());
  slot->initialized = 1u;
  stamp_empty_frame(slot);
  return TOF_STATUS_OK;
}

static int init_rear_slot(void)
{
  TofL8SlotRuntime_t *slot = slot_for(TOF_L8_SENSOR_REAR);
  TofL8ProbeResult_t i2c_probe;
  TofL8ProbeResult_t spi_probe;
  TofL8TransportHandle_t candidate;

  pulse_reset(TOF_L8_SENSOR_REAR);

  TofL8Transport_InitI2c(&candidate, TOF_L8_I2C_BUS_3,
                         TOF_L8_DEFAULT_I2C_ADDR_8BIT);
  probe_transport(TOF_L8_SENSOR_REAR, slot, &candidate, &i2c_probe);

  TofL8Transport_InitSpi(&candidate, TOF_L8_SPI_BUS_1, TOF_L8_GPIO_PB2_D8);
  probe_transport(TOF_L8_SENSOR_REAR, slot, &candidate, &spi_probe);

  int i2c_alive = probe_alive(&i2c_probe);
  int spi_alive = probe_alive(&spi_probe);
  TofL8TransportKind_t selected =
      TofL8Transport_ChooseProbe(i2c_alive, spi_alive);
  if (selected == TOF_L8_TRANSPORT_NONE) {
    log_fmt("VL53L8 rear probe: no sensor i2c_rd=%u i2c_alive=%u "
            "spi_rd=%u spi_alive=%u\r\n",
            (unsigned)i2c_probe.alive_read, (unsigned)i2c_probe.alive,
            (unsigned)spi_probe.alive_read, (unsigned)spi_probe.alive);
    return TOF_STATUS_NO_SENSOR;
  }
  if (selected == TOF_L8_TRANSPORT_AMBIGUOUS) {
    log_fmt("VL53L8 rear probe: ambiguous transport i2c_alive=%u "
            "spi_alive=%u\r\n",
            (unsigned)i2c_probe.alive, (unsigned)spi_probe.alive);
    return TOF_STATUS_IO;
  }

  return init_slot_from_probe(TOF_L8_SENSOR_REAR, slot,
                              (selected == TOF_L8_TRANSPORT_I2C)
                                  ? &i2c_probe
                                  : &spi_probe);
}

static int init_front_slot(void)
{
  TofL8SlotRuntime_t *slot = slot_for(TOF_L8_SENSOR_FRONT);
  TofL8ProbeResult_t spi_probe;
  TofL8TransportHandle_t candidate;

  pulse_reset(TOF_L8_SENSOR_FRONT);

  TofL8Transport_InitSpi(&candidate, TOF_L8_SPI_BUS_1, TOF_L8_GPIO_PA2_D10);
  probe_transport(TOF_L8_SENSOR_FRONT, slot, &candidate, &spi_probe);

  if (!probe_alive(&spi_probe)) {
    log_fmt("VL53L8 front probe: no sensor spi_rd=%u spi_alive=%u\r\n",
            (unsigned)spi_probe.alive_read, (unsigned)spi_probe.alive);
    return TOF_STATUS_NO_SENSOR;
  }

  return init_slot_from_probe(TOF_L8_SENSOR_FRONT, slot, &spi_probe);
}

static uint8_t config_matches(const Tof_Config_t *a, const Tof_Config_t *b)
{
  return a->sensor_type    == b->sensor_type
      && a->layout         == b->layout
      && a->profile        == b->profile
      && a->frequency_hz   == b->frequency_hz
      && a->integration_ms == b->integration_ms;
}

static uint8_t all_streaming_match(const Tof_Config_t *cfg)
{
  uint8_t active = 0u;
  for (uint8_t i = 0u; i < (uint8_t)TOF_L8_SENSOR_COUNT; ++i) {
    TofL8SlotRuntime_t *slot = &g_slots[i];
    if (!slot->initialized || slot->driver_dead) continue;
    active = 1u;
    if (!slot->streaming || !config_matches(cfg, &g_cfg)) return 0u;
  }
  return active;
}

static int configure_slot(TofL8SensorId_t sensor_id,
                          TofL8SlotRuntime_t *slot,
                          const Tof_Config_t *cfg)
{
  if (!slot || !slot->initialized || slot->driver_dead) {
    return TOF_STATUS_NO_SENSOR;
  }

  uint8_t s = vl53l8cx_set_resolution(&slot->dev,
                                      resolution_for_layout(cfg->layout));
  s |= vl53l8cx_set_ranging_mode(&slot->dev, VL53L8CX_RANGING_MODE_AUTONOMOUS);
  s |= vl53l8cx_set_ranging_frequency_hz(&slot->dev, cfg->frequency_hz);
  s |= vl53l8cx_set_integration_time_ms(&slot->dev,
                                        integration_for_config(cfg));
  if (s != VL53L8CX_STATUS_OK) {
    log_fmt("VL53L8 %s config failed status=%u\r\n",
            sensor_name(sensor_id), (unsigned)s);
    slot->driver_dead = 1u;
    return TOF_STATUS_IO;
  }

  s = vl53l8cx_start_ranging(&slot->dev);
  if (s != VL53L8CX_STATUS_OK) {
    log_fmt("VL53L8 %s start failed status=%u\r\n",
            sensor_name(sensor_id), (unsigned)s);
    slot->driver_dead = 1u;
    return TOF_STATUS_IO;
  }

  slot->streaming = 1u;
  slot->seq = 0u;
  slot->last_frame_log_tick = 0u;
  slot->last_frame_log_seq = 0u;
  stamp_empty_frame(slot);
  log_fmt("VL53L8 %s stream start layout=%u zones=%u hz=%u it=%u "
          "readBytes=%lu\r\n",
          sensor_name(sensor_id), (unsigned)g_cfg.layout,
          (unsigned)slot->frame_latest.zone_count,
          (unsigned)g_cfg.frequency_hz, (unsigned)g_cfg.integration_ms,
          (unsigned long)slot->dev.data_read_size);
  return TOF_STATUS_OK;
}

int TofL8_Init(void)
{
  if (g_initialized) return TOF_STATUS_OK;

  memset(g_slots, 0, sizeof(g_slots));
  stamp_empty_frame(slot_for(TOF_L8_SENSOR_REAR));
  stamp_empty_frame(slot_for(TOF_L8_SENSOR_FRONT));

  log_fmt("VL53L8 init phase=gpio tick=%lu\r\n",
          (unsigned long)HAL_GetTick());
  configure_gpio();

  int rear_rc = init_rear_slot();
  int front_rc = init_front_slot();

  uint8_t found = 0u;
  for (uint8_t i = 0u; i < (uint8_t)TOF_L8_SENSOR_COUNT; ++i) {
    if (g_slots[i].initialized && !g_slots[i].driver_dead) found++;
  }
  if (found == 0u) {
    log_fmt("VL53L8 init: no usable sensors rear_rc=%d front_rc=%d\r\n",
            rear_rc, front_rc);
    return (rear_rc != TOF_STATUS_NO_SENSOR) ? rear_rc : front_rc;
  }

  g_initialized = 1u;
  int rc = TofL8_Configure(&g_cfg);
  if (rc == TOF_STATUS_OK) {
    log_fmt("VL53L8 ready sensors=0x%02X L=%u Hz=%u IT=%u\r\n",
            (unsigned)TofL8_AvailableMask(), (unsigned)g_cfg.layout,
            (unsigned)g_cfg.frequency_hz, (unsigned)g_cfg.integration_ms);
  }
  g_last_configure_tick = 0u;
  return rc;
}

int TofL8_EnsureInitialized(void)
{
  return g_initialized ? TOF_STATUS_OK : TofL8_Init();
}

int TofL8_Configure(const Tof_Config_t *cfg)
{
  int rc = TofL8_ValidateConfig(cfg);
  if (rc != TOF_STATUS_OK) return rc;
  if (!g_initialized) return TOF_STATUS_NO_SENSOR;

  if (all_streaming_match(cfg)) return TOF_STATUS_OK;

  uint32_t now = HAL_GetTick();
  if (TofL8Debounce_ShouldSkip(now, g_last_configure_tick,
                               TOF_L8_RECONFIGURE_DEBOUNCE_MS)) {
    return TOF_STATUS_OK;
  }

  for (uint8_t i = 0u; i < (uint8_t)TOF_L8_SENSOR_COUNT; ++i) {
    (void)stop_stream((TofL8SensorId_t)i, &g_slots[i]);
  }

  HAL_Delay(2);

  g_cfg = *cfg;
  if (g_cfg.integration_ms < 2u) {
    g_cfg.integration_ms = integration_for_config(&g_cfg);
  }

  uint8_t ok_count = 0u;
  int last_error = TOF_STATUS_NO_SENSOR;
  for (uint8_t i = 0u; i < (uint8_t)TOF_L8_SENSOR_COUNT; ++i) {
    rc = configure_slot((TofL8SensorId_t)i, &g_slots[i], &g_cfg);
    if (rc == TOF_STATUS_OK) {
      ok_count++;
    } else if (rc != TOF_STATUS_NO_SENSOR) {
      last_error = rc;
    }
  }

  if (ok_count == 0u) return last_error;
  g_last_configure_tick = now;
  return TOF_STATUS_OK;
}

void TofL8_Process(void)
{
  if (!g_initialized) return;

  for (uint8_t i = 0u; i < (uint8_t)TOF_L8_SENSOR_COUNT; ++i) {
    TofL8SlotRuntime_t *slot = &g_slots[i];
    if (!slot->initialized || !slot->streaming || slot->driver_dead) continue;

    uint8_t ready = 0;
    uint8_t s = vl53l8cx_check_data_ready(&slot->dev, &ready);
    if (s != VL53L8CX_STATUS_OK || ready == 0u) continue;

    memset(&slot->results, 0, sizeof(slot->results));
    s = vl53l8cx_get_ranging_data(&slot->dev, &slot->results);
    if (s != VL53L8CX_STATUS_OK) continue;

    slot->seq++;
    slot->frame_latest.sensor_type = TOF_SENSOR_VL53L8CX;
    slot->frame_latest.layout = g_cfg.layout;
    slot->frame_latest.zone_count = (uint8_t)(g_cfg.layout * g_cfg.layout);
    slot->frame_latest.profile = g_cfg.profile;
    slot->frame_latest.seq = slot->seq;
    slot->frame_latest.tick_ms = HAL_GetTick();

    uint8_t zones = slot->frame_latest.zone_count;
    if (zones > TOF_MAX_ZONES) zones = TOF_MAX_ZONES;
    for (uint8_t z = 0; z < zones; ++z) {
      int16_t d = slot->results.distance_mm[z];
      uint8_t targets = slot->results.nb_target_detected[z];
      slot->frame_latest.zones[z].range_mm =
          (targets == 0u || d < 0) ? 0u : (uint16_t)d;
      slot->frame_latest.zones[z].status = slot->results.target_status[z];
      slot->frame_latest.zones[z].flags = targets;
    }
    slot->has_new_frame = 1;

    uint32_t frame_tick = slot->frame_latest.tick_ms;
    if (slot->seq == 1u ||
        (frame_tick - slot->last_frame_log_tick) >=
            TOF_L8_FRAME_LOG_INTERVAL_MS) {
      uint8_t layout = slot->frame_latest.layout;
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
      for (uint8_t z = 0u; z < zones; ++z) {
        uint16_t range_mm = slot->frame_latest.zones[z].range_mm;
        if (slot->frame_latest.zones[z].flags > 0u && range_mm > 0u &&
            TofL8_StatusIsRangeValid(slot->frame_latest.zones[z].status)) {
          target_zones++;
          if (range_mm < min_mm) min_mm = range_mm;
          if (range_mm > max_mm) max_mm = range_mm;
        }
      }
      if (target_zones == 0u) min_mm = 0u;
      uint32_t frame_delta = (slot->last_frame_log_seq == 0u)
                                 ? slot->seq
                                 : (slot->seq - slot->last_frame_log_seq);
      slot->last_frame_log_tick = frame_tick;
      slot->last_frame_log_seq = slot->seq;
      log_fmt("VL53L8 %s frame layout=%u zones=%u seq=%lu fps=%lu "
              "targetZones=%u min=%u max=%u z0=%u/%u/%u zLast=%u/%u/%u "
              "center=%u,%u,%u,%u cst=%u,%u,%u,%u cn=%u,%u,%u,%u\r\n",
              sensor_name((TofL8SensorId_t)i), (unsigned)layout,
              (unsigned)zones, (unsigned long)slot->seq,
              (unsigned long)frame_delta, (unsigned)target_zones,
              (unsigned)min_mm, (unsigned)max_mm,
              (unsigned)logged_range_at(slot, 0u),
              (unsigned)logged_status_at(slot, 0u),
              (unsigned)logged_flags_at(slot, 0u),
              (unsigned)logged_range_at(slot, last),
              (unsigned)logged_status_at(slot, last),
              (unsigned)logged_flags_at(slot, last),
              (unsigned)logged_range_at(slot, cc00),
              (unsigned)logged_range_at(slot, cc01),
              (unsigned)logged_range_at(slot, cc10),
              (unsigned)logged_range_at(slot, cc11),
              (unsigned)logged_status_at(slot, cc00),
              (unsigned)logged_status_at(slot, cc01),
              (unsigned)logged_status_at(slot, cc10),
              (unsigned)logged_status_at(slot, cc11),
              (unsigned)logged_flags_at(slot, cc00),
              (unsigned)logged_flags_at(slot, cc01),
              (unsigned)logged_flags_at(slot, cc10),
              (unsigned)logged_flags_at(slot, cc11));
      log_4x4_grid((TofL8SensorId_t)i, slot);
    }
  }
}

const Tof_Frame_t *TofL8_GetLatestFrame(void)
{
  TofL8SlotRuntime_t *slot = default_slot();
  return slot ? &slot->frame_latest : 0;
}

int TofL8_HasNewFrame(void)
{
  TofL8SlotRuntime_t *slot = default_slot();
  return slot ? slot->has_new_frame : 0;
}

void TofL8_ClearNewFrame(void)
{
  TofL8SlotRuntime_t *slot = default_slot();
  if (slot) slot->has_new_frame = 0;
}

int TofL8_IsInitialized(void) { return (int)g_initialized; }

int TofL8_IsDriverDead(void)
{
  TofL8SlotRuntime_t *slot = default_slot();
  return slot ? (int)slot->driver_dead : 0;
}

const Tof_Frame_t *TofL8_GetLatestFrameForSensor(TofL8SensorId_t sensor_id)
{
  TofL8SlotRuntime_t *slot = slot_for(sensor_id);
  return slot ? &slot->frame_latest : 0;
}

int TofL8_HasNewFrameForSensor(TofL8SensorId_t sensor_id)
{
  TofL8SlotRuntime_t *slot = slot_for(sensor_id);
  return slot ? slot->has_new_frame : 0;
}

void TofL8_ClearNewFrameForSensor(TofL8SensorId_t sensor_id)
{
  TofL8SlotRuntime_t *slot = slot_for(sensor_id);
  if (slot) slot->has_new_frame = 0;
}

int TofL8_IsSensorAvailable(TofL8SensorId_t sensor_id)
{
  TofL8SlotRuntime_t *slot = slot_for(sensor_id);
  return slot && slot->initialized && slot->streaming && !slot->driver_dead;
}

int TofL8_IsDriverDeadForSensor(TofL8SensorId_t sensor_id)
{
  TofL8SlotRuntime_t *slot = slot_for(sensor_id);
  return slot ? (int)slot->driver_dead : 0;
}

uint8_t TofL8_AvailableMask(void)
{
  uint8_t mask = 0u;
  for (uint8_t i = 0u; i < (uint8_t)TOF_L8_SENSOR_COUNT; ++i) {
    if (TofL8_IsSensorAvailable((TofL8SensorId_t)i)) {
      mask |= (uint8_t)(1u << i);
    }
  }
  return mask;
}
