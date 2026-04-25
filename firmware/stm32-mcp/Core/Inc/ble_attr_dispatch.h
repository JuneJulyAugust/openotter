/* SPDX-License-Identifier: BSD-3-Clause */
/*
 * ble_attr_dispatch — pure routing predicate for GATT attribute writes.
 *
 * BlueNRG-MS reports attribute writes via EVT_BLUE_GATT_ATTRIBUTE_MODIFIED
 * with the *attribute* handle, which is the *characteristic* handle + 1
 * (the value descriptor sits one slot after the declaration). Writing
 * the bare comparison `attr_mod->attr_handle == (charHandle + 1)` looks
 * fine — but if `charHandle` is still zero because aci_gatt_add_char()
 * failed during init (see the FE44 GATT slot postmortem,
 * docs/dev/09-ble-gatt-slot-bug-postmortem.md), the comparison matches
 * attribute handle 1 — the GATT service declaration of every BlueNRG
 * service. Any attribute write at all then gets misrouted into the
 * application command path, with attacker-controlled bytes interpreted
 * as a steering/throttle/mode payload.
 *
 * BleAttrDispatch_IsValueWrite() rejects this case explicitly: a zero
 * characteristic handle means "not initialized" and never matches.
 *
 * Pure, host-testable.
 */

#ifndef BLE_ATTR_DISPATCH_H
#define BLE_ATTR_DISPATCH_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Returns true iff `received_attr_handle` is the value-handle of the
 * characteristic identified by `char_handle` AND the characteristic was
 * actually registered (char_handle != 0).
 */
bool BleAttrDispatch_IsValueWrite(uint16_t received_attr_handle,
                                  uint16_t char_handle);

#ifdef __cplusplus
}
#endif

#endif /* BLE_ATTR_DISPATCH_H */
