/* SPDX-License-Identifier: BSD-3-Clause */
/*
 * ble_command — pure decoder for the FE41 control payload.
 *
 * Wire format (6 bytes, little-endian):
 *   int16_t steering_us       offset 0
 *   int16_t throttle_us       offset 2
 *   int16_t velocity_mm_per_s offset 4   (signed; negative = reversing)
 *
 * Authority: docs/superpowers/specs/2026-04-23-stm32-reverse-safety-and-protocol-design.md §3.1
 *
 * The legacy 4-byte payload (no velocity) is intentionally rejected — see the
 * spec note on the v0.4.0 breaking wire change.
 */

#ifndef BLE_COMMAND_H
#define BLE_COMMAND_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define BLE_COMMAND_PAYLOAD_BYTES 6

typedef struct {
  int16_t steering_us;
  int16_t throttle_us;
  int16_t velocity_mm_per_s;
} BleCommand_t;

typedef enum {
  BLE_CMD_OK         = 0,
  BLE_CMD_TOO_SHORT  = 1, /* len < 6 — legacy 4 B writes land here */
  BLE_CMD_NULL_INPUT = 2,
} BleCommandStatus_t;

/*
 * Parse an FE41 attribute write into a structured command.
 *
 * Pure. No side effects, no globals. Returns BLE_CMD_OK and fills *out only
 * when the payload is at least 6 bytes long. Excess bytes beyond byte 5 are
 * ignored — the wire format is a fixed 6-byte prefix.
 *
 * Behavior is identical to the previous inline parser in ble_app.c so the
 * extraction is observably a no-op.
 */
BleCommandStatus_t BleCommand_Parse(const uint8_t *data,
                                    uint16_t len,
                                    BleCommand_t *out);

#ifdef __cplusplus
}
#endif

#endif /* BLE_COMMAND_H */
