/* SPDX-License-Identifier: BSD-3-Clause */
/*
 * ble_gatt_layout — BlueNRG-MS Max_Attribute_Records accounting.
 *
 * The BlueNRG-MS GATT stack pre-allocates one attribute record per
 * declaration, value, and CCCD slot inside a service. If the count passed to
 * aci_gatt_add_serv() is too small, the LAST aci_gatt_add_char() silently
 * fails with BLE_STATUS_INSUFFICIENT_RESOURCES — leaving that characteristic
 * undiscoverable. See docs/dev/09-ble-gatt-slot-bug-postmortem.md for the
 * incident this module exists to prevent.
 *
 * Slot accounting per characteristic:
 *   - declaration:               always 1
 *   - value:                     always 1
 *   - CCCD (notify or indicate): 1 only if .notify or .indicate is set
 *
 * Plus 1 for the service declaration itself.
 *
 * Pure (HAL-free, no globals).
 */

#ifndef BLE_GATT_LAYOUT_H
#define BLE_GATT_LAYOUT_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
  bool notify;     /* CHAR_PROP_NOTIFY   → consumes a CCCD slot */
  bool indicate;   /* CHAR_PROP_INDICATE → consumes a CCCD slot */
  /* Other props (read/write/wwr) do NOT consume extra slots — only decl + value. */
} BleGattCharSpec_t;

/*
 * Compute the Max_Attribute_Records value to pass to aci_gatt_add_serv().
 *
 * Returns 1 (service declaration) plus, for each characteristic in the array,
 * 2 (decl + value) plus 1 if notify or indicate is set.
 *
 * If chars is NULL, returns 1 (just the service declaration).
 */
uint8_t BleGattLayout_RequiredSlots(const BleGattCharSpec_t *chars,
                                    uint8_t char_count);

#ifdef __cplusplus
}
#endif

#endif /* BLE_GATT_LAYOUT_H */
