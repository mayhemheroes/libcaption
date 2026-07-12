/* Behavioral known-answer oracle for libcaption.
 *
 * Upstream ships only one live unit binary (unit_tests/test_wrap, run separately
 * by mayhem/test.sh with a golden-output diff); its other two unit files
 * (eia608_test.c, test_sei.c) reference APIs that were removed/renamed and are
 * disabled in upstream's CMakeLists, so they no longer compile. This oracle is a
 * genuine behavioral supplement: it asserts KNOWN ANSWERS of the public API that
 * the ts2srt fuzz harness also exercises (EIA-608 control-code round-trips and the
 * caption-frame text encode/decode round-trip), so a patch that no-ops the library
 * FAILS here. Each check prints RESULT and the program exits non-zero on any failure.
 */
#include "caption.h"
#include "eia608.h"
#include "utf8.h"
#include <stdio.h>
#include <string.h>

static int g_passed = 0, g_failed = 0;

static void check(const char* name, int ok)
{
    if (ok) {
        ++g_passed;
        printf("ok   - %s\n", name);
    } else {
        ++g_failed;
        printf("FAIL - %s\n", name);
    }
}

/* All EIA-608 control commands must survive a parse -> re-encode round-trip. */
static int control_roundtrip_ok(void)
{
    int checked = 0;
    for (int i = 0; i <= 0x3FFF; ++i) {
        uint16_t code1 = eia608_parity(((i << 1) & 0x7F00) | (i & 0x7F));
        if (eia608_is_control(code1)) {
            int cc;
            eia608_control_t cmd = eia608_parse_control(code1, &cc);
            uint16_t code2 = eia608_control_command(cmd, cc);
            ++checked;
            if (code1 != code2) {
                return 0;
            }
        }
    }
    /* Known answer: exactly 96 control codes across both channels. */
    return checked == 96;
}

/* A caption frame populated from known text must read back byte-for-byte. */
static int frame_text_roundtrip_ok(const char* in)
{
    caption_frame_t frame;
    caption_frame_init(&frame);
    caption_frame_from_text(&frame, in);
    char buf[CAPTION_FRAME_TEXT_BYTES];
    memset(buf, 0, sizeof(buf));
    caption_frame_to_text(&frame, buf);
    return 0 == strcmp(buf, in);
}

/* eia608 parity is a deterministic known-answer table. */
static int parity_known_answer_ok(void)
{
    /* 0x20 already has odd parity, so it is left unchanged. */
    if (eia608_parity_byte(0x20) != 0x20) {
        return 0;
    }
    /* 0x41 needs the high parity bit set -> 0xC1. */
    if (eia608_parity_byte(0x41) != 0xC1) {
        return 0;
    }
    return eia608_parity_varify(eia608_parity_word(0x2020));
}

int main(void)
{
    check("eia608 control-code parse/encode round-trip (96 codes)", control_roundtrip_ok());
    check("caption_frame text round-trip 'HELLO WORLD'", frame_text_roundtrip_ok("HELLO WORLD"));
    check("caption_frame text round-trip 'CLOSED CAPTION TEST'", frame_text_roundtrip_ok("CLOSED CAPTION TEST"));
    check("eia608 parity known-answer", parity_known_answer_ok());

    printf("SELFTEST TESTS=%d PASSED=%d FAILED=%d\n", g_passed + g_failed, g_passed, g_failed);
    return g_failed == 0 ? 0 : 1;
}
