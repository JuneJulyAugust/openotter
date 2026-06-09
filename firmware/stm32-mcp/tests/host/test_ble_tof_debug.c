#include "ble_tof_debug.h"

#include <assert.h>
#include <stdint.h>
#include <string.h>

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

static void test_config_queue_copies_latest_payload_for_main_loop(void)
{
  BLE_TofDebugConfigQueue_t queue;
  BLE_TofDebugConfigQueue_Init(&queue);

  uint8_t first[BLE_TOF_DEBUG_CONFIG_PAYLOAD_SIZE] = {
      2u, 4u, 1u, 10u, 20u, 0u, 0u, 0u, BLE_TOF_DEBUG_ROLE_REAR,
  };
  uint8_t second[BLE_TOF_DEBUG_CONFIG_PAYLOAD_SIZE] = {
      2u, 8u, 1u, 15u, 20u, 0u, 0u, 0u, BLE_TOF_DEBUG_ROLE_FRONT,
  };
  uint8_t out[BLE_TOF_DEBUG_CONFIG_PAYLOAD_SIZE] = {0};
  uint16_t out_len = 0u;

  assert(BLE_TofDebugConfigQueue_Push(&queue, first, sizeof(first)) == 0);
  assert(BLE_TofDebugConfigQueue_HasPending(&queue));
  assert(BLE_TofDebugConfigQueue_Push(&queue, second, sizeof(second)) == 0);

  assert(BLE_TofDebugConfigQueue_Pop(&queue, out, sizeof(out), &out_len) == 0);
  assert(out_len == sizeof(second));
  assert(memcmp(out, second, sizeof(second)) == 0);
  assert(!BLE_TofDebugConfigQueue_HasPending(&queue));
}

static void test_config_queue_rejects_bad_payloads(void)
{
  BLE_TofDebugConfigQueue_t queue;
  BLE_TofDebugConfigQueue_Init(&queue);

  uint8_t payload[BLE_TOF_DEBUG_CONFIG_PAYLOAD_SIZE + 1u] = {0};
  uint8_t out[BLE_TOF_DEBUG_CONFIG_PAYLOAD_SIZE] = {0};
  uint16_t out_len = 0u;

  assert(BLE_TofDebugConfigQueue_Push(
             &queue, payload, BLE_TOF_DEBUG_CONFIG_PREFIX_SIZE - 1u) < 0);
  assert(BLE_TofDebugConfigQueue_Push(
             &queue, payload, sizeof(payload)) < 0);
  assert(BLE_TofDebugConfigQueue_Push(0, payload,
                                      BLE_TOF_DEBUG_CONFIG_PREFIX_SIZE) < 0);
  assert(BLE_TofDebugConfigQueue_Push(&queue, 0,
                                      BLE_TOF_DEBUG_CONFIG_PREFIX_SIZE) < 0);
  assert(!BLE_TofDebugConfigQueue_HasPending(&queue));
  assert(BLE_TofDebugConfigQueue_Pop(&queue, out, sizeof(out), &out_len) < 0);
}

static void test_config_queue_bad_payload_clears_stale_pending_config(void)
{
  BLE_TofDebugConfigQueue_t queue;
  BLE_TofDebugConfigQueue_Init(&queue);

  uint8_t good[BLE_TOF_DEBUG_CONFIG_PAYLOAD_SIZE] = {
      2u, 4u, 1u, 10u, 20u, 0u, 0u, 0u, BLE_TOF_DEBUG_ROLE_REAR,
  };
  uint8_t bad[BLE_TOF_DEBUG_CONFIG_PREFIX_SIZE - 1u] = {0};

  assert(BLE_TofDebugConfigQueue_Push(&queue, good, sizeof(good)) == 0);
  assert(BLE_TofDebugConfigQueue_HasPending(&queue));
  assert(BLE_TofDebugConfigQueue_Push(&queue, bad, sizeof(bad)) < 0);
  assert(!BLE_TofDebugConfigQueue_HasPending(&queue));
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
  test_config_queue_copies_latest_payload_for_main_loop();
  test_config_queue_rejects_bad_payloads();
  test_config_queue_bad_payload_clears_stale_pending_config();
  return 0;
}
