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
  f->sensor_type = TOF_SENSOR_VL53L8CX;
  f->layout = layout;
  f->zone_count = (uint8_t)(layout * layout);
  f->profile = TOF_PROFILE_L8_CONTINUOUS;
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
  expect_u8("sensor type", payload[1], TOF_SENSOR_VL53L8CX);
  expect_u8("layout", payload[2], 4u);
  expect_u8("zone count", payload[3], 16u);
  expect_u8("seq b0", payload[4], 0x78u);
  expect_u8("seq b3", payload[7], 0x12u);
  expect_u8("tick b0", payload[8], 0x04u);
  expect_u8("tick b3", payload[11], 0x01u);
  expect_u8("len b0", payload[12], 80u);
  expect_u8("len b1", payload[13], 0u);
  expect_u8("profile", payload[14], TOF_PROFILE_L8_CONTINUOUS);
  expect_u8("reserved", payload[15], 0u);
  expect_u8("first range low", payload[16], 100u);
  expect_u8("first range high", payload[17], 0u);
  expect_u8("first status", payload[18], 0u);
  expect_u8("first flags", payload[19], 0x80u);
  expect_u8("last range low", payload[76], 115u);
  expect_u8("last range high", payload[77], 0u);
  expect_u8("last status", payload[78], 15u);
  expect_u8("last flags", payload[79], 0x8Fu);

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
  for (uint8_t i = 10u; i < TOF_FRAME_CHUNK_SIZE; ++i) {
    expect_u8("final chunk zero pad", chunk[i], 0u);
  }
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

  int rc = TofFrameCodec_Serialize(NULL, payload, sizeof(payload), &len);
  expect_u32("null frame rejected", (uint32_t)rc, TOF_CODEC_ERR_BAD_FRAME);

  rc = TofFrameCodec_Serialize(&f, NULL, sizeof(payload), &len);
  expect_u32("null output rejected", (uint32_t)rc, TOF_CODEC_ERR_BAD_FRAME);

  rc = TofFrameCodec_Serialize(&f, payload, sizeof(payload), NULL);
  expect_u32("null length rejected", (uint32_t)rc, TOF_CODEC_ERR_BAD_FRAME);

  f.layout = 0;
  rc = TofFrameCodec_Serialize(&f, payload, sizeof(payload), &len);
  expect_u32("zero layout rejected", (uint32_t)rc, TOF_CODEC_ERR_BAD_FRAME);

  fill_frame(&f, 8);
  f.zone_count = 0;
  rc = TofFrameCodec_Serialize(&f, payload, sizeof(payload), &len);
  expect_u32("zero zone count rejected", (uint32_t)rc, TOF_CODEC_ERR_BAD_FRAME);

  fill_frame(&f, 8);
  f.zone_count = (uint8_t)(TOF_MAX_ZONES + 1u);
  rc = TofFrameCodec_Serialize(&f, payload, sizeof(payload), &len);
  expect_u32("too many zones rejected", (uint32_t)rc, TOF_CODEC_ERR_BAD_FRAME);

  fill_frame(&f, 4);
  rc = TofFrameCodec_Serialize(&f, payload, 79u, &len);
  expect_u32("small output rejected", (uint32_t)rc, TOF_CODEC_ERR_TOO_SMALL);

  fill_frame(&f, 8);
  f.zone_count = 63;
  rc = TofFrameCodec_Serialize(&f, payload, sizeof(payload), &len);
  expect_u32("bad zone count rejected", (uint32_t)rc, TOF_CODEC_ERR_BAD_FRAME);
}

static void test_chunk_count_boundaries(void)
{
  expect_u8("zero payload chunks", TofFrameCodec_ChunkCount(0u), 0u);
  expect_u8("one byte chunks", TofFrameCodec_ChunkCount(1u), 1u);
  expect_u8("one full chunk", TofFrameCodec_ChunkCount(18u), 1u);
  expect_u8("two chunks", TofFrameCodec_ChunkCount(19u), 2u);
  expect_u8("8x8 chunks", TofFrameCodec_ChunkCount(272u), 16u);
}

static void test_rejects_bad_chunk(void)
{
  Tof_Frame_t f;
  uint8_t payload[TOF_FRAME_MAX_PAYLOAD];
  uint8_t chunk[TOF_FRAME_CHUNK_SIZE];
  uint16_t len = 0;
  fill_frame(&f, 8);
  int rc = TofFrameCodec_Serialize(&f, payload, sizeof(payload), &len);
  expect_u32("8x8 serialize for chunk rejection rc", (uint32_t)rc, TOF_CODEC_OK);

  rc = TofFrameCodec_MakeChunk(NULL, len, f.seq, 0u, chunk);
  expect_u32("null payload rejected", (uint32_t)rc, TOF_CODEC_ERR_BAD_FRAME);

  rc = TofFrameCodec_MakeChunk(payload, len, f.seq, 0u, NULL);
  expect_u32("null chunk output rejected", (uint32_t)rc, TOF_CODEC_ERR_BAD_FRAME);

  rc = TofFrameCodec_MakeChunk(payload, 0u, f.seq, 0u, chunk);
  expect_u32("zero payload len rejected", (uint32_t)rc, TOF_CODEC_ERR_BAD_FRAME);

  rc = TofFrameCodec_MakeChunk(payload, 272u, f.seq, 16u, payload);
  expect_u32("bad chunk index rejected", (uint32_t)rc, TOF_CODEC_ERR_BAD_CHUNK);

  rc = TofFrameCodec_MakeChunk(payload,
                               (uint16_t)(TOF_FRAME_CHUNK_DATA * 129u),
                               f.seq,
                               0u,
                               chunk);
  expect_u32("too many chunks rejected", (uint32_t)rc, TOF_CODEC_ERR_BAD_CHUNK);
}

int main(void)
{
  test_4x4_payload_and_chunks();
  test_8x8_payload_and_chunks();
  test_rejects_bad_frame();
  test_chunk_count_boundaries();
  test_rejects_bad_chunk();

  if (g_fails) {
    fprintf(stderr, "\n%d failure(s)\n", g_fails);
    return 1;
  }
  printf("PASS all TofFrameCodec assertions\n");
  return 0;
}
