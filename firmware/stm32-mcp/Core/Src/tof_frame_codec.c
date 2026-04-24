/* SPDX-License-Identifier: BSD-3-Clause */

#include "tof_frame_codec.h"

#include <string.h>

static void put_u16_le(uint8_t *p, uint16_t v)
{
  p[0] = (uint8_t)(v & 0xFFu);
  p[1] = (uint8_t)(v >> 8);
}

static void put_u32_le(uint8_t *p, uint32_t v)
{
  p[0] = (uint8_t)(v & 0xFFu);
  p[1] = (uint8_t)((v >> 8) & 0xFFu);
  p[2] = (uint8_t)((v >> 16) & 0xFFu);
  p[3] = (uint8_t)((v >> 24) & 0xFFu);
}

static uint8_t valid_frame_shape(const Tof_Frame_t *frame)
{
  if (frame == NULL) return 0;
  if (frame->layout == 0u) return 0;
  if (frame->zone_count == 0u || frame->zone_count > TOF_MAX_ZONES) return 0;
  if (frame->zone_count != (uint8_t)(frame->layout * frame->layout)) return 0;
  return 1;
}

int TofFrameCodec_Serialize(const Tof_Frame_t *frame,
                            uint8_t *out,
                            uint16_t out_cap,
                            uint16_t *out_len)
{
  if (!valid_frame_shape(frame) || out == NULL || out_len == NULL) {
    return TOF_CODEC_ERR_BAD_FRAME;
  }

  uint16_t need = (uint16_t)(TOF_FRAME_HEADER_SIZE +
                            frame->zone_count * TOF_FRAME_ZONE_SIZE);
  if (out_cap < need) return TOF_CODEC_ERR_TOO_SMALL;

  out[0] = TOF_FRAME_V2_VERSION;
  out[1] = frame->sensor_type;
  out[2] = frame->layout;
  out[3] = frame->zone_count;
  put_u32_le(&out[4], frame->seq);
  put_u32_le(&out[8], frame->tick_ms);
  put_u16_le(&out[12], need);
  out[14] = frame->profile;
  out[15] = 0;

  for (uint8_t i = 0; i < frame->zone_count; ++i) {
    uint16_t off = (uint16_t)(TOF_FRAME_HEADER_SIZE +
                              i * TOF_FRAME_ZONE_SIZE);
    put_u16_le(&out[off], frame->zones[i].range_mm);
    out[off + 2u] = frame->zones[i].status;
    out[off + 3u] = frame->zones[i].flags;
  }

  *out_len = need;
  return TOF_CODEC_OK;
}

uint8_t TofFrameCodec_ChunkCount(uint16_t payload_len)
{
  if (payload_len == 0u) return 0;
  return (uint8_t)((payload_len + TOF_FRAME_CHUNK_DATA - 1u) /
                   TOF_FRAME_CHUNK_DATA);
}

int TofFrameCodec_MakeChunk(const uint8_t *payload,
                            uint16_t payload_len,
                            uint32_t seq,
                            uint8_t chunk_index,
                            uint8_t out_chunk[TOF_FRAME_CHUNK_SIZE])
{
  if (payload == NULL || out_chunk == NULL || payload_len == 0u) {
    return TOF_CODEC_ERR_BAD_FRAME;
  }

  uint8_t chunks = TofFrameCodec_ChunkCount(payload_len);
  if (chunk_index >= chunks || chunks > 0x80u) return TOF_CODEC_ERR_BAD_CHUNK;

  uint16_t off = (uint16_t)(chunk_index * TOF_FRAME_CHUNK_DATA);
  uint16_t remaining = (uint16_t)(payload_len - off);
  uint8_t n = (remaining > TOF_FRAME_CHUNK_DATA) ?
      TOF_FRAME_CHUNK_DATA : (uint8_t)remaining;

  memset(out_chunk, 0, TOF_FRAME_CHUNK_SIZE);
  out_chunk[0] = chunk_index;
  if (chunk_index == (uint8_t)(chunks - 1u)) {
    out_chunk[0] |= 0x80u;
  }
  out_chunk[1] = (uint8_t)(seq & 0xFFu);
  memcpy(&out_chunk[2], &payload[off], n);
  return TOF_CODEC_OK;
}
