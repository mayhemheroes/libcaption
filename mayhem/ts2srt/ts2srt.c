/* libFuzzer harness for libcaption's MPEG-TS -> caption -> SRT pipeline.
 *
 * Drives the exact code path of examples/ts2srt.c (ts_parse_packet ->
 * mpeg_bitstream_parse -> caption_frame -> srt_cue_from_caption_frame), but
 * over an in-memory buffer instead of a file, so the fuzzer instruments and
 * explores the TS demux + CEA-708/EIA-608 caption decoders directly. This is
 * an in-process conversion of the original file-input `ts2srt` Mayhem target
 * (same code path; parity preserved).
 */
#include "srt.h"
#include "ts.h"
#include <stdint.h>
#include <stddef.h>
#include <string.h>

int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size)
{
    ts_t ts;
    srt_t* srt = 0;
    mpeg_bitstream_t mpegbs;
    caption_frame_t frame;

    ts_init(&ts);
    caption_frame_init(&frame);
    mpeg_bitstream_init(&mpegbs);
    srt = srt_new();
    if (!srt) {
        return 0;
    }

    size_t off = 0;
    while (size - off >= TS_PACKET_SIZE) {
        const uint8_t* pkt = data + off;
        off += TS_PACKET_SIZE;

        if (LIBCAPTION_READY == ts_parse_packet(&ts, pkt)) {
            double dts = ts_dts_seconds(&ts);
            double cts = ts_cts_seconds(&ts);
            int err = 0;
            while (ts.size) {
                size_t bytes_read = mpeg_bitstream_parse(&mpegbs, &frame, ts.data, ts.size, ts.stream_type, dts, cts);
                ts.data += bytes_read, ts.size -= bytes_read;
                switch (mpeg_bitstream_status(&mpegbs)) {
                default:
                case LIBCAPTION_ERROR:
                    mpeg_bitstream_init(&mpegbs);
                    err = 1;
                    break;
                case LIBCAPTION_OK:
                    break;
                case LIBCAPTION_READY:
                    srt_cue_from_caption_frame(&frame, srt);
                    break;
                }
                if (err || bytes_read == 0) {
                    break;
                }
            }
            if (err) {
                break;
            }
        }
    }

    while (mpeg_bitstream_flush(&mpegbs, &frame)) {
        if (mpeg_bitstream_status(&mpegbs)) {
            srt_cue_from_caption_frame(&frame, srt);
        }
    }

    srt_free(srt);
    return 0;
}
