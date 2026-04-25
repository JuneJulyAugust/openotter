/* SPDX-License-Identifier: BSD-3-Clause */
#include "ble_gatt_layout.h"

#include <stddef.h>

uint8_t BleGattLayout_RequiredSlots(const BleGattCharSpec_t *chars,
                                    uint8_t char_count) {
  uint8_t slots = 1u; /* service declaration */
  if (chars == NULL) return slots;

  for (uint8_t i = 0; i < char_count; ++i) {
    slots = (uint8_t)(slots + 2u); /* declaration + value */
    if (chars[i].notify || chars[i].indicate) {
      slots = (uint8_t)(slots + 1u); /* CCCD */
    }
  }
  return slots;
}
