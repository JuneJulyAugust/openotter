/* SPDX-License-Identifier: BSD-3-Clause */
/******************************************************************************
 * BLE GATT service for VL53L8 ToF debug frames (svc 0xFE60).
 *
 *   FE61  config  write/write-w/o-resp, 9 B fixed
 *   FE62  frame   notify, 20 B fixed chunks
 *   FE63  status  notify + read, 4 B fixed
 *
 * Frame publish strategy: BLE_Tof_Process is called once per main-loop
 * iteration. When the selected debug ToF reports a new frame and a central is connected,
 * we update the FE62 characteristic value (which auto-pushes a notification
 * if the CCCD enabled it). Status is refreshed once per second.
 ******************************************************************************/

#include "ble_tof.h"

#include "ble_app.h"
#include "ble_attr_dispatch.h"
#include "ble_tof_debug.h"
#include "ble_tof_policy.h"
#include "common.h"
#include "tl_types.h"
#include "tl_ble_hci.h"
#include "svc_ctl.h"
#include "ble_lib.h"
#include "blesvc.h"

#include "tof_frame_codec.h"
#include "tof_l8.h"
#include "tof_types.h"

#include <stdarg.h>
#include <stdio.h>
#include <string.h>

extern UART_HandleTypeDef huart1;

typedef enum {
  TOF_PENDING_NONE = 0,
  TOF_PENDING_V2,
} BLE_TofPendingProtocol_t;

typedef struct {
  uint16_t svc_handle;
  uint16_t config_char_handle;
  uint16_t frame_char_handle;
  uint16_t status_char_handle;

  /* Status & rate tracking */
  uint32_t last_status_tick;
  uint32_t last_rate_window_tick;
  uint32_t last_rate_window_seq;
  uint32_t last_published_seq;
  uint8_t  scan_hz;
  uint8_t  state;       /* 0 idle, 1 running, 2 error */
  uint8_t  last_error;
  uint8_t  debug_role;

  /* Frame chunk transmitter state. pending_chunk == 0 means idle; values
   * 1..pending_chunk_count are the next chunk to push. */
  uint8_t  pending_chunk;
  uint8_t  pending_chunk_count;
  uint16_t pending_len;
  uint32_t pending_seq;
  BLE_TofPendingProtocol_t pending_protocol;
  uint8_t  pending_buf[TOF_FRAME_MAX_PAYLOAD];

  /* Diagnostic counters reported via UART. */
  uint32_t l8_frames_seen;
  uint32_t chunks_pushed;
  uint32_t chunks_failed;
  uint32_t snapshots_taken;
  uint8_t  safety_config_pending;
  uint8_t  safety_config_ready;
  uint32_t safety_config_retry_tick;
  uint8_t  status_publish_pending;
  BLE_TofDebugConfigQueue_t config_queue;
} BLE_TofContext_t;

static BLE_TofContext_t s_tof;

#define STATUS_REFRESH_MS               1000u
/* Boot-time grace before the first VL53L8CX init runs. Keeps the multi-second
 * blocking firmware download out of the earliest startup window where the
 * BLE stack is still settling. Independent of BLE connection state — the
 * sensor must come up whether or not the iOS app ever connects. */
#define SAFETY_CONFIG_BOOT_GRACE_MS     1000u
#define SAFETY_CONFIG_RETRY_MS          3000u
#define SAFETY_CONFIG_HANDSHAKE_DEFER_MS 250u

static SVCCTL_EvtAckStatus_t BLE_Tof_EventHandler(void *event);

static int tick_reached(uint32_t now, uint32_t target)
{
  return (int32_t)(now - target) >= 0;
}

static void log_prefix(void)
{
  char buf[16];
  int n = snprintf(buf, sizeof(buf), "[%lu] ",
                   (unsigned long)HAL_GetTick());
  if (n > 0) {
    HAL_UART_Transmit(&huart1, (uint8_t *)buf, (uint16_t)n, 100);
  }
}

static void log_str(const char *s)
{
  log_prefix();
  HAL_UART_Transmit(&huart1, (const uint8_t *)s, (uint16_t)strlen(s), 100);
}

static void log_fmt(const char *fmt, ...)
{
  char buf[160];
  va_list ap;
  va_start(ap, fmt);
  int n = vsnprintf(buf, sizeof(buf), fmt, ap);
  va_end(ap);
  if (n > 0) {
    log_prefix();
    HAL_UART_Transmit(&huart1, (uint8_t *)buf, (uint16_t)n, 100);
  }
}


static void publish_status(void)
{
  BLE_TofStatusPayload_t st = {
      .state      = s_tof.state,
      .last_error = s_tof.last_error,
      .scan_hz    = s_tof.scan_hz,
      .debug      = BLE_TofDebugStatusPad(s_tof.debug_role,
                                          TofL8_AvailableMask()),
  };
  (void)aci_gatt_update_char_value(s_tof.svc_handle, s_tof.status_char_handle,
                                   0, sizeof(st), (uint8_t *)&st);
}

static TofL8SensorId_t selected_l8_sensor_id(void)
{
  return (s_tof.debug_role == BLE_TOF_DEBUG_ROLE_FRONT)
      ? TOF_L8_SENSOR_FRONT
      : TOF_L8_SENSOR_REAR;
}

static const char *debug_role_name(void)
{
  return (s_tof.debug_role == BLE_TOF_DEBUG_ROLE_FRONT) ? "front" : "rear";
}

static void reset_stream_state(void)
{
  s_tof.last_published_seq    = 0;
  s_tof.last_rate_window_seq  = 0;
  s_tof.last_rate_window_tick = HAL_GetTick();
  s_tof.scan_hz               = 0;
  s_tof.pending_chunk         = 0;
  s_tof.pending_chunk_count   = 0;
  s_tof.pending_len           = 0;
  s_tof.pending_protocol      = TOF_PENDING_NONE;
}

static void snapshot_l8_if_ready(void)
{
  TofL8SensorId_t sensor_id = selected_l8_sensor_id();
  if (s_tof.pending_chunk != 0 ||
      !TofL8_IsSensorAvailable(sensor_id) ||
      !TofL8_HasNewFrameForSensor(sensor_id)) {
    return;
  }

  const Tof_Frame_t *f = TofL8_GetLatestFrameForSensor(sensor_id);
  if (f->seq == s_tof.last_published_seq) {
    TofL8_ClearNewFrameForSensor(sensor_id);
    return;
  }

  uint16_t payload_len = 0;
  int rc = TofFrameCodec_Serialize(f, s_tof.pending_buf,
                                   sizeof(s_tof.pending_buf), &payload_len);
  if (rc != TOF_CODEC_OK) {
    s_tof.last_error = (uint8_t)TOF_STATUS_BAD_CONFIG;
    s_tof.state = BLE_TOF_STATE_ERROR;
    TofL8_ClearNewFrameForSensor(sensor_id);
    return;
  }

  s_tof.pending_seq         = f->seq;
  s_tof.pending_len         = payload_len;
  s_tof.pending_chunk_count = TofFrameCodec_ChunkCount(payload_len);
  s_tof.pending_protocol    = TOF_PENDING_V2;
  s_tof.pending_chunk       = 1;
  s_tof.snapshots_taken++;
  TofL8_ClearNewFrameForSensor(sensor_id);
}

static tBleStatus publish_pending_chunk(void)
{
  uint8_t idx = (uint8_t)(s_tof.pending_chunk - 1u);
  uint8_t buf[TOF_FRAME_CHUNK_SIZE];

  if (s_tof.pending_protocol == TOF_PENDING_V2) {
    int rc = TofFrameCodec_MakeChunk(s_tof.pending_buf, s_tof.pending_len,
                                     s_tof.pending_seq, idx, buf);
    if (rc != TOF_CODEC_OK) return BLE_STATUS_FAILED;
  } else {
    return BLE_STATUS_FAILED;
  }

  return aci_gatt_update_char_value(s_tof.svc_handle, s_tof.frame_char_handle,
                                    0, sizeof(buf), buf);
}

static uint32_t current_debug_seq(void)
{
  return TofL8_GetLatestFrameForSensor(selected_l8_sensor_id())->seq;
}

static void request_status_publish(void)
{
  s_tof.status_publish_pending = 1u;
}

static void publish_pending_status_if_needed(void)
{
  if (!s_tof.status_publish_pending || !BLE_App_IsConnected()) return;
  s_tof.status_publish_pending = 0u;
  publish_status();
}

int BLE_Tof_Init(void)
{
  uint16_t uuid;
  tBleStatus ret;

  memset(&s_tof, 0, sizeof(s_tof));
  s_tof.state = BLE_TOF_STATE_RUNNING;
  s_tof.debug_role = BLE_TOF_DEBUG_ROLE_REAR;
  BLE_TofDebugConfigQueue_Init(&s_tof.config_queue);

  SVCCTL_RegisterSvcHandler(BLE_Tof_EventHandler);

  /* Service: 1 (svc) + 2 per char × 3 chars + 1 CCCD per notify char × 2 = 9 */
  uuid = OPENOTTER_TOF_SVC_UUID;
  ret = aci_gatt_add_serv(UUID_TYPE_16, (const uint8_t *)&uuid, PRIMARY_SERVICE,
                          1 + 2 * 3 + 2, &s_tof.svc_handle);
  if (ret != BLE_STATUS_SUCCESS) {
    log_str("BLE_Tof: add_serv failed\r\n");
    return -1;
  }

  /* FE61 — config (write + write-w/o-resp), fixed 9 B */
  uuid = OPENOTTER_TOF_CONFIG_CHAR_UUID;
  ret = aci_gatt_add_char(s_tof.svc_handle, UUID_TYPE_16,
                          (const uint8_t *)&uuid,
                          sizeof(BLE_TofConfigPayload_t),
                          CHAR_PROP_WRITE_WITHOUT_RESP | CHAR_PROP_WRITE,
                          ATTR_PERMISSION_NONE,
                          GATT_NOTIFY_ATTRIBUTE_WRITE,
                          10, /* encryKeySize */
                          0,  /* fixed length */
                          &s_tof.config_char_handle);
  if (ret != BLE_STATUS_SUCCESS) { log_str("BLE_Tof: add_char FE61 failed\r\n"); return -1; }

  /* FE62 — frame chunk (notify), fixed 20 B. Frame is reassembled by the
   * client from consecutive notifications. */
  uuid = OPENOTTER_TOF_FRAME_CHAR_UUID;
  ret = aci_gatt_add_char(s_tof.svc_handle, UUID_TYPE_16,
                          (const uint8_t *)&uuid,
                          TOF_FRAME_CHUNK_SIZE,
                          CHAR_PROP_NOTIFY,
                          ATTR_PERMISSION_NONE,
                          GATT_DONT_NOTIFY_EVENTS,
                          10,
                          0,
                          &s_tof.frame_char_handle);
  if (ret != BLE_STATUS_SUCCESS) { log_str("BLE_Tof: add_char FE62 failed\r\n"); return -1; }

  /* FE63 — status (notify + read), fixed 4 B */
  uuid = OPENOTTER_TOF_STATUS_CHAR_UUID;
  ret = aci_gatt_add_char(s_tof.svc_handle, UUID_TYPE_16,
                          (const uint8_t *)&uuid,
                          sizeof(BLE_TofStatusPayload_t),
                          CHAR_PROP_NOTIFY | CHAR_PROP_READ,
                          ATTR_PERMISSION_NONE,
                          GATT_DONT_NOTIFY_EVENTS,
                          10,
                          0,
                          &s_tof.status_char_handle);
  if (ret != BLE_STATUS_SUCCESS) { log_str("BLE_Tof: add_char FE63 failed\r\n"); return -1; }

  s_tof.last_status_tick      = HAL_GetTick();
  s_tof.last_rate_window_tick = HAL_GetTick();
  s_tof.safety_config_pending = 1u;
  s_tof.safety_config_ready   = 0u;
  /* Defer the first init by the boot grace so it does not collide with
   * the BLE stack's own startup. After this initial delay the VL53L8 driver
   * comes up regardless of BLE connection state. */
  s_tof.safety_config_retry_tick = HAL_GetTick() + SAFETY_CONFIG_BOOT_GRACE_MS;
  publish_status();
  log_str("BLE_Tof ready\r\n");
  return 0;
}

void BLE_Tof_RequestSafetyConfig(void)
{
  BLE_TofDebugConfigQueue_Clear(&s_tof.config_queue);
  s_tof.safety_config_pending = 1u;
  s_tof.safety_config_ready = 0u;
  s_tof.safety_config_retry_tick = 0u;
}

int BLE_Tof_SafetyConfigReady(void)
{
  return s_tof.safety_config_ready != 0u &&
         s_tof.safety_config_pending == 0u;
}

static int boot_grace_allows_debug_config(uint32_t now)
{
  if (TofL8_IsInitialized()) return 1;
  if (!s_tof.safety_config_pending) return 1;
  if (s_tof.safety_config_retry_tick == 0u) return 1;
  return tick_reached(now, s_tof.safety_config_retry_tick);
}

static void apply_config_write(const uint8_t *data, uint16_t len);

static uint8_t process_pending_debug_config(uint32_t now)
{
  if (!BLE_TofDebugConfigQueue_HasPending(&s_tof.config_queue)) return 0u;

  if (!BLE_App_IsConnected()) {
    BLE_TofDebugConfigQueue_Clear(&s_tof.config_queue);
    return 1u;
  }

  if (BLE_App_GetMode() != OPENOTTER_MODE_DEBUG) {
    BLE_TofDebugConfigQueue_Clear(&s_tof.config_queue);
    s_tof.last_error = (uint8_t)TOF_STATUS_LOCKED_IN_DRIVE;
    s_tof.state = BLE_TOF_STATE_RUNNING;
    request_status_publish();
    return 1u;
  }

  if (!boot_grace_allows_debug_config(now)) {
    return 0u;
  }

  uint8_t data[BLE_TOF_DEBUG_CONFIG_PAYLOAD_SIZE] = {0};
  uint16_t len = 0u;
  if (BLE_TofDebugConfigQueue_Pop(&s_tof.config_queue, data, sizeof(data),
                                  &len) < 0) {
    s_tof.last_error = (uint8_t)TOF_STATUS_BAD_CONFIG;
    s_tof.state = BLE_TOF_STATE_RUNNING;
    request_status_publish();
    return 1u;
  }

  apply_config_write(data, len);
  return 1u;
}

void BLE_Tof_Process(void)
{
  uint32_t now = HAL_GetTick();

  /* VL53L8 driver init / safety config — runs regardless of BLE connection
   * state so the reverse-safety sensor (and the LED2 frame heartbeat)
   * comes up at boot whether or not the iOS app ever connects. The boot
   * grace lives on safety_config_retry_tick (seeded in Init); subsequent
   * retries also use that field. */
  uint8_t safety_retry_due =
      (s_tof.safety_config_retry_tick == 0u ||
       tick_reached(now, s_tof.safety_config_retry_tick)) ? 1u : 0u;
  if (s_tof.safety_config_pending && safety_retry_due) {
    if (BLE_App_HandshakePending()) {
      s_tof.safety_config_retry_tick =
          HAL_GetTick() + SAFETY_CONFIG_HANDSHAKE_DEFER_MS;
    } else if (BLE_App_GetMode() == OPENOTTER_MODE_DRIVE) {
      log_fmt("BLE_Tof safety_config fire mode=%u tick=%lu\r\n",
              (unsigned)BLE_App_GetMode(), (unsigned long)now);
      /* Drive: apply the full safety config (driver init + 4x4 30 Hz).
       * Clears pending only on success; failure schedules a retry. */
      s_tof.safety_config_pending = 0u;
      BLE_Tof_EnforceSafetyConfig();
      log_fmt("BLE_Tof enforce_done ready=%u err=%u tick=%lu\r\n",
              (unsigned)s_tof.safety_config_ready,
              (unsigned)s_tof.last_error,
              (unsigned long)HAL_GetTick());
      if (!s_tof.safety_config_ready) {
        s_tof.safety_config_pending = 1u;
        s_tof.safety_config_retry_tick =
            HAL_GetTick() + SAFETY_CONFIG_RETRY_MS;
      }
    }
  }

  uint8_t handled_debug_config = process_pending_debug_config(now);
  if (s_tof.safety_config_pending && safety_retry_due &&
      BLE_App_GetMode() != OPENOTTER_MODE_DRIVE &&
      !handled_debug_config) {
    /* Debug/Park must not run VL53L8 init/config from a BLE event callback.
     * If iOS has queued a debug FE61 write, process_pending_debug_config()
     * applies it from this main-loop context. Without a queued config, keep
     * retry bookkeeping alive for the next Drive edge. */
    s_tof.safety_config_retry_tick = HAL_GetTick() + SAFETY_CONFIG_RETRY_MS;
  }

  publish_pending_status_if_needed();

  if (!BLE_App_IsConnected()) return;

  if (!BLE_Tof_FrameStreamAllowed((uint8_t)BLE_App_GetMode())) {
    uint32_t since_status = now - s_tof.last_status_tick;
    if (since_status >= STATUS_REFRESH_MS) {
      s_tof.last_status_tick = now;
      publish_status();
    }
    return;
  }

  TofL8SensorId_t selected_id = selected_l8_sensor_id();
  uint8_t had_new_l8 =
      (TofL8_IsSensorAvailable(selected_id) &&
       TofL8_HasNewFrameForSensor(selected_id)) ? 1u : 0u;

  /* If no chunk transmission in flight, snapshot the latest frame. */
  snapshot_l8_if_ready();

  if (had_new_l8) {
    s_tof.l8_frames_seen++;
  }

  /* Drain pending chunks, metered to avoid overflowing the BlueNRG-MS
   * TX notification buffer (~4 slots). Remaining chunks are pushed in
   * subsequent main-loop iterations. A TX-buffer-full return is not a
   * data loss — the chunk will be retried next call. */
  uint8_t batch = 0;
  while (s_tof.pending_chunk > 0 &&
         s_tof.pending_chunk <= s_tof.pending_chunk_count &&
         batch < 4u) {
    tBleStatus ret = publish_pending_chunk();
    if (ret != BLE_STATUS_SUCCESS) {
      s_tof.chunks_failed++;
      break; /* TX buffer full — retry next iteration, not a failure */
    }
    s_tof.chunks_pushed++;
    s_tof.pending_chunk++;
    batch++;
  }
  if (s_tof.pending_chunk > s_tof.pending_chunk_count) {
    s_tof.last_published_seq = s_tof.pending_seq;
    s_tof.pending_chunk = 0;
    s_tof.pending_protocol = TOF_PENDING_NONE;
  }

  /* Defer status update and UART log while chunks are in flight.
   * publish_status steals a TX buffer slot from chunk drain, and
   * log_fmt blocks the main loop for ~7ms preventing chunk retries. */
  if (s_tof.pending_chunk != 0) return;

  /* Recompute scan rate over a 1 s sliding window and push status. */
  uint32_t since_status = now - s_tof.last_status_tick;
  if (since_status >= STATUS_REFRESH_MS) {
    uint32_t seq = current_debug_seq();
    uint32_t window_ms = now - s_tof.last_rate_window_tick;
    if (window_ms > 0) {
      uint32_t delta = seq - s_tof.last_rate_window_seq;
      uint32_t hz    = (delta * 1000u + window_ms / 2u) / window_ms;
      s_tof.scan_hz  = (hz > 255u) ? 255u : (uint8_t)hz;
    }
    s_tof.last_rate_window_tick = now;
    s_tof.last_rate_window_seq  = seq;
    s_tof.last_status_tick      = now;
    publish_status();
    /* Safe to log here — we only reach this branch when pending_chunk == 0
     * (gate above) and have just stolen one TX slot for status. The
     * UART blocks ~3-7 ms; chunk drain has nothing in flight to starve. */
    log_fmt("L8 dbg: seen=%lu snap=%lu push=%lu fail=%lu mode=%u "
            "role=%s avail=0x%02x dbgseq=%lu pubseq=%lu hz=%u\r\n",
            (unsigned long)s_tof.l8_frames_seen,
            (unsigned long)s_tof.snapshots_taken,
            (unsigned long)s_tof.chunks_pushed,
            (unsigned long)s_tof.chunks_failed,
            (unsigned)BLE_App_GetMode(),
            debug_role_name(),
            (unsigned)TofL8_AvailableMask(),
            (unsigned long)seq,
            (unsigned long)s_tof.last_published_seq,
            (unsigned)s_tof.scan_hz);
  }
}

static void apply_config_write(const uint8_t *data, uint16_t len)
{
  /* Reject NULL data outright. The BlueNRG stack is documented to pass a
   * valid pointer, but a single defensive guard here is cheaper than the
   * eventual hard fault if that contract ever breaks (e.g. a future stack
   * version, a corrupted attribute write packet). */
  if (data == NULL || len < sizeof(Tof_Config_t)) {
    s_tof.last_error = (uint8_t)TOF_STATUS_BAD_CONFIG;
    s_tof.state      = BLE_TOF_STATE_ERROR;
    publish_status();
    return;
  }

  if (data[0] != TOF_SENSOR_VL53L8CX) {
    s_tof.last_error = (uint8_t)TOF_STATUS_BAD_CONFIG;
    s_tof.state = BLE_TOF_STATE_RUNNING;
    publish_status();
    return;
  }

  if (!BLE_Tof_ConfigWriteAllowed((uint8_t)BLE_App_GetMode(), data[0])) {
    s_tof.last_error = (uint8_t)TOF_STATUS_LOCKED_IN_DRIVE;
    s_tof.state      = BLE_TOF_STATE_RUNNING;
    publish_status();
    return;
  }

  uint8_t requested_role = BLE_TOF_DEBUG_ROLE_REAR;
  if (BLE_TofDebugRoleFromConfigPayload(data, len, &requested_role) < 0) {
    s_tof.last_error = (uint8_t)TOF_STATUS_BAD_CONFIG;
    s_tof.state      = BLE_TOF_STATE_RUNNING;
    publish_status();
    return;
  }

  Tof_Config_t cfg;
  memcpy(&cfg, data, sizeof(cfg));

  int rc = TofL8_EnsureInitialized();
  if (rc == TOF_STATUS_OK) {
    rc = TofL8_Configure(&cfg);
  }
  if (rc != TOF_STATUS_BAD_CONFIG) {
    s_tof.debug_role = requested_role;
    reset_stream_state();
  }

  BLE_TofStatusDecision_t decision = BLE_Tof_StatusForResult(rc);
  s_tof.last_error = decision.last_error;
  s_tof.state = decision.state;
  publish_status();
}

static SVCCTL_EvtAckStatus_t BLE_Tof_EventHandler(void *Event)
{
  SVCCTL_EvtAckStatus_t ack = SVCCTL_EvtNotAck;
  hci_event_pckt *event_pckt =
      (hci_event_pckt *)(((hci_uart_pckt *)Event)->data);

  if (event_pckt->evt != EVT_VENDOR) return ack;

  evt_blue_aci *blue_evt = (evt_blue_aci *)event_pckt->data;
  if (blue_evt->ecode != EVT_BLUE_GATT_ATTRIBUTE_MODIFIED) return ack;

  evt_gatt_attr_modified *attr_mod = (evt_gatt_attr_modified *)blue_evt->data;
  if (BleAttrDispatch_IsValueWrite(attr_mod->attr_handle,
                                   s_tof.config_char_handle)) {
    ack = SVCCTL_EvtAck;
    if (BLE_TofDebugConfigQueue_Push(&s_tof.config_queue,
                                     attr_mod->att_data,
                                     attr_mod->data_length) < 0) {
      s_tof.last_error = (uint8_t)TOF_STATUS_BAD_CONFIG;
      s_tof.state = BLE_TOF_STATE_RUNNING;
      request_status_publish();
    }
  }
  return ack;
}

void BLE_Tof_EnforceSafetyConfig(void)
{
  Tof_Config_t cfg = {
      .sensor_type = TOF_SENSOR_VL53L8CX,
      .layout = 4,
      .profile = TOF_PROFILE_L8_CONTINUOUS,
      .frequency_hz = 30,
      .integration_ms = 20,
      .budget_ms = 0,
  };

  int rc = TofL8_EnsureInitialized();
  if (rc == TOF_STATUS_OK) {
    rc = TofL8_Configure(&cfg);
  }
  reset_stream_state();
  s_tof.safety_config_ready = (rc == TOF_STATUS_OK) ? 1u : 0u;
  BLE_TofStatusDecision_t decision = BLE_Tof_StatusForResult(rc);
  s_tof.last_error = decision.last_error;
  s_tof.state = decision.state;
  publish_status();
}
