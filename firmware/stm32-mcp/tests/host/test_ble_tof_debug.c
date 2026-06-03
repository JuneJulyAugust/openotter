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

static void test_status_pad_decodes_invalid_role_bits_as_rear(void)
{
  uint8_t pad = 0x32u;

  assert(BLE_TofDebugStatusPad_SelectedRole(pad) ==
         BLE_TOF_DEBUG_ROLE_REAR);
  assert(BLE_TofDebugStatusPad_AvailableMask(pad) == 0x03u);
}

static void test_config_role_uses_rear_for_legacy_8_byte_payload(void)
{
  uint8_t payload[BLE_TOF_DEBUG_CONFIG_PREFIX_SIZE] = {0};
  uint8_t role = 0xffu;

  assert(BLE_TofDebugRoleFromConfigPayload(
             payload, sizeof(payload), &role) == 0);
  assert(role == BLE_TOF_DEBUG_ROLE_REAR);
}

static void test_config_role_reads_front_from_9_byte_payload(void)
{
  uint8_t payload[BLE_TOF_DEBUG_CONFIG_PAYLOAD_SIZE] = {0};
  uint8_t role = 0xffu;
  payload[BLE_TOF_DEBUG_CONFIG_PREFIX_SIZE] = BLE_TOF_DEBUG_ROLE_FRONT;

  assert(BLE_TofDebugRoleFromConfigPayload(
             payload, sizeof(payload), &role) == 0);
  assert(role == BLE_TOF_DEBUG_ROLE_FRONT);
}

static void test_config_role_rejects_invalid_inputs(void)
{
  uint8_t payload[BLE_TOF_DEBUG_CONFIG_PAYLOAD_SIZE] = {0};
  uint8_t role = BLE_TOF_DEBUG_ROLE_REAR;
  payload[BLE_TOF_DEBUG_CONFIG_PREFIX_SIZE] = 2u;

  assert(BLE_TofDebugRoleFromConfigPayload(
             payload, BLE_TOF_DEBUG_CONFIG_PREFIX_SIZE - 1u, &role) < 0);
  assert(BLE_TofDebugRoleFromConfigPayload(
             payload, sizeof(payload), &role) < 0);
  assert(BLE_TofDebugRoleFromConfigPayload(
             0, sizeof(payload), &role) < 0);
  assert(BLE_TofDebugRoleFromConfigPayload(
             payload, sizeof(payload), 0) < 0);
}

int main(void)
{
  test_role_validation();
  test_status_pad_packs_selected_role_and_available_mask();
  test_status_pad_ignores_invalid_mask_bits();
  test_status_pad_decodes_invalid_role_bits_as_rear();
  test_config_role_uses_rear_for_legacy_8_byte_payload();
  test_config_role_reads_front_from_9_byte_payload();
  test_config_role_rejects_invalid_inputs();
  return 0;
}
