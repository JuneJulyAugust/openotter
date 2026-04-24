/* SPDX-License-Identifier: BSD-3-Clause */

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "tof_frame_codec.h"
#include "tof_types.h"

static int g_fails = 0;

static void expect_u32(const char *label, uint32_t got, uint32_t want)
{
  if (got != want) {
    fprintf(stderr, "FAIL %s: got %lu want %lu\n",
            label, (unsigned long)got, (unsigned long)want);
    g_fails++;
  }
}

static void expect_u8(const char *label, uint8_t got, uint8_t want)
{
  if (got != want) {
    fprintf(stderr, "FAIL %s: got %u want %u\n", label, got, want);
    g_fails++;
  }
}

static void fill_frame(Tof_Frame_t *f, uint8_t layout)
{
  memset(f, 0, sizeof(*f));
  f->sensor_type = TOF_SENSOR_VL53L5CX;
  f->layout = layout;
  f->zone_count = (uint8_t)(layout * layout);
  f->profile = TOF_PROFILE_L5_CONTINUOUS;
  f->seq = 0x12345678u;
  f->tick_ms = 0x01020304u;
  for (uint8_t i = 0; i < f->zone_count; ++i) {
    f->zones[i].range_mm = (uint16_t)(100u + i);
    f->zones[i].status = i;
    f->zones[i].flags = (uint8_t)(0x80u | i);
  }
}

static void test_4x4_payload_and_chunks(void)
{
  Tof_Frame_t f;
  uint8_t payload[TOF_FRAME_MAX_PAYLOAD];
  uint8_t chunk[TOF_FRAME_CHUNK_SIZE];
  fill_frame(&f, 4);

  uint16_t len = 0;
  int rc = TofFrameCodec_Serialize(&f, payload, sizeof(payload), &len);
  expect_u32("4x4 serialize rc", (uint32_t)rc, TOF_CODEC_OK);
  expect_u32("4x4 payload length", len, 80u);
  expect_u8("version", payload[0], TOF_FRAME_V2_VERSION);
  expect_u8("sensor type", payload[1], TOF_SENSOR_VL53L5CX);
  expect_u8("layout", payload[2], 4u);
  expect_u8("zone count", payload[3], 16u);

  uint8_t chunks = TofFrameCodec_ChunkCount(len);
  expect_u8("4x4 chunk count", chunks, 5u);
  expect_u32("chunk data bytes", TOF_FRAME_CHUNK_DATA, 18u);

  rc = TofFrameCodec_MakeChunk(payload, len, f.seq, 0, chunk);
  expect_u32("4x4 first chunk rc", (uint32_t)rc, TOF_CODEC_OK);
  expect_u8("first chunk idx", chunk[0], 0u);
  expect_u8("first chunk seq low", chunk[1], 0x78u);

  rc = TofFrameCodec_MakeChunk(payload, len, f.seq, (uint8_t)(chunks - 1u), chunk);
  expect_u32("4x4 final chunk rc", (uint32_t)rc, TOF_CODEC_OK);
  expect_u8("final chunk last flag", chunk[0], (uint8_t)(0x80u | (chunks - 1u)));
}

static void test_8x8_payload_and_chunks(void)
{
  Tof_Frame_t f;
  uint8_t payload[TOF_FRAME_MAX_PAYLOAD];
  fill_frame(&f, 8);

  uint16_t len = 0;
  int rc = TofFrameCodec_Serialize(&f, payload, sizeof(payload), &len);
  expect_u32("8x8 serialize rc", (uint32_t)rc, TOF_CODEC_OK);
  expect_u32("8x8 payload length", len, 272u);
  expect_u8("8x8 zone count", payload[3], 64u);
  expect_u8("8x8 chunk count", TofFrameCodec_ChunkCount(len), 16u);
}

static void test_rejects_bad_frame(void)
{
  Tof_Frame_t f;
  uint8_t payload[TOF_FRAME_MAX_PAYLOAD];
  uint16_t len = 0;
  fill_frame(&f, 8);

  f.zone_count = 63;
  int rc = TofFrameCodec_Serialize(&f, payload, sizeof(payload), &len);
  expect_u32("bad zone count rejected", (uint32_t)rc, TOF_CODEC_ERR_BAD_FRAME);

  fill_frame(&f, 8);
  rc = TofFrameCodec_MakeChunk(payload, 272u, f.seq, 16u, payload);
  expect_u32("bad chunk index rejected", (uint32_t)rc, TOF_CODEC_ERR_BAD_CHUNK);
}

int main(void)
{
  test_4x4_payload_and_chunks();
  test_8x8_payload_and_chunks();
  test_rejects_bad_frame();

  if (g_fails) {
    fprintf(stderr, "\n%d failure(s)\n", g_fails);
    return 1;
  }
  printf("PASS all TofFrameCodec assertions\n");
  return 0;
}
