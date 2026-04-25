/* SPDX-License-Identifier: BSD-3-Clause */
#include "ble_command.h"

#include <string.h>

BleCommandStatus_t BleCommand_Parse(const uint8_t *data,
                                    uint16_t len,
                                    BleCommand_t *out) {
  if (data == NULL || out == NULL) return BLE_CMD_NULL_INPUT;
  if (len < BLE_COMMAND_PAYLOAD_BYTES) return BLE_CMD_TOO_SHORT;

  /* Wire format is little-endian; the MCU is also little-endian, so a memcpy
   * into the matching int16 fields is correct. The packed struct order in
   * BLE_CommandPayload_t (ble_app.h) is steering, throttle, velocity. */
  int16_t fields[3];
  memcpy(fields, data, sizeof(fields));
  out->steering_us       = fields[0];
  out->throttle_us       = fields[1];
  out->velocity_mm_per_s = fields[2];
  return BLE_CMD_OK;
}
