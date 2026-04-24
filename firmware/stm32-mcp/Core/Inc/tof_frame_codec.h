/* SPDX-License-Identifier: BSD-3-Clause */
#ifndef TOF_FRAME_CODEC_H
#define TOF_FRAME_CODEC_H

#include <stdint.h>

#include "tof_types.h"

#ifdef __cplusplus
extern "C" {
#endif

#define TOF_FRAME_V2_VERSION      2u
#define TOF_FRAME_HEADER_SIZE    16u
#define TOF_FRAME_ZONE_SIZE       4u
#define TOF_FRAME_MAX_PAYLOAD   (TOF_FRAME_HEADER_SIZE + TOF_MAX_ZONES * TOF_FRAME_ZONE_SIZE)
#define TOF_FRAME_CHUNK_SIZE     20u
#define TOF_FRAME_CHUNK_DATA     18u

typedef enum {
  TOF_CODEC_OK             = 0,
  TOF_CODEC_ERR_BAD_FRAME  = 1,
  TOF_CODEC_ERR_TOO_SMALL  = 2,
  TOF_CODEC_ERR_BAD_CHUNK  = 3,
} TofCodec_Status_t;

int TofFrameCodec_Serialize(const Tof_Frame_t *frame,
                            uint8_t *out,
                            uint16_t out_cap,
                            uint16_t *out_len);

uint8_t TofFrameCodec_ChunkCount(uint16_t payload_len);

int TofFrameCodec_MakeChunk(const uint8_t *payload,
                            uint16_t payload_len,
                            uint32_t seq,
                            uint8_t chunk_index,
                            uint8_t out_chunk[TOF_FRAME_CHUNK_SIZE]);

#ifdef __cplusplus
}
#endif

#endif /* TOF_FRAME_CODEC_H */
