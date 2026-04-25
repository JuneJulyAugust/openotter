/* SPDX-License-Identifier: BSD-3-Clause */
#include "ble_attr_dispatch.h"

bool BleAttrDispatch_IsValueWrite(uint16_t received_attr_handle,
                                  uint16_t char_handle) {
  if (char_handle == 0u) return false;
  return received_attr_handle == (uint16_t)(char_handle + 1u);
}
