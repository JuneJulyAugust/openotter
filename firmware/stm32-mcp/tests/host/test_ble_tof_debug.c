#include "ble_tof_debug.h"

#include <assert.h>
#include <stdint.h>

static void test_role_validation(void)
{
  assert(BLE_TofDebugRole_IsValid(BLE_TOF_DEBUG_ROLE_REAR));
  assert(BLE_TofDebugRole_IsValid(BLE_TOF_DEBUG_ROLE_FRONT));
  assert(!BLE_TofDebugRole_IsValid(2u));
}

static void test_status_pad_packs_selected_role_and_available_mask(void)
{
  uint8_t pad = BLE_TofDebugStatusPad(BLE_TOF_DEBUG_ROLE_FRONT, 0x03u);

  assert(BLE_TofDebugStatusPad_SelectedRole(pad) ==
         BLE_TOF_DEBUG_ROLE_FRONT);
  assert(BLE_TofDebugStatusPad_AvailableMask(pad) == 0x03u);
}

static void test_status_pad_ignores_invalid_mask_bits(void)
{
  uint8_t pad = BLE_TofDebugStatusPad(BLE_TOF_DEBUG_ROLE_REAR, 0xF3u);

  assert(BLE_TofDebugStatusPad_SelectedRole(pad) ==
         BLE_TOF_DEBUG_ROLE_REAR);
  assert(BLE_TofDebugStatusPad_AvailableMask(pad) == 0x03u);
}

int main(void)
{
  test_role_validation();
  test_status_pad_packs_selected_role_and_available_mask();
  test_status_pad_ignores_invalid_mask_bits();
  return 0;
}
