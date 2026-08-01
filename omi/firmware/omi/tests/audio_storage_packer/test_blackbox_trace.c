#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

#include "../../src/lib/core/blackbox_trace.h"

static void test_trace_expires_without_accepting_late_event(void)
{
    blackbox_trace_event_t storage[4];
    blackbox_trace_t trace;
    blackbox_trace_init(&trace, storage, 4U);
    blackbox_trace_start(&trace, 1000U, 2U);

    assert(blackbox_trace_record(&trace, 2999U, 1U, 0U, 10, 20));
    assert(!blackbox_trace_record(&trace, 3000U, 2U, 0U, 30, 40));
    assert(!trace.enabled);
    assert(trace.count == 1U);
}

static void test_wrap_reports_cursor_loss_and_preserves_order(void)
{
    blackbox_trace_event_t storage[3];
    blackbox_trace_event_t out[3];
    blackbox_trace_t trace;
    blackbox_trace_init(&trace, storage, 3U);
    blackbox_trace_start(&trace, 0U, 100U);

    for (int32_t i = 1; i <= 5; i++) {
        assert(blackbox_trace_record(&trace, (uint64_t) i, (uint16_t) i, 0U, i, -i));
    }

    uint32_t oldest = 0U;
    uint32_t next = 0U;
    bool overwritten = false;
    size_t count = blackbox_trace_copy(&trace, 1U, out, 3U, &oldest, &next, &overwritten);
    assert(count == 3U);
    assert(overwritten);
    assert(oldest == 3U);
    assert(next == 6U);
    assert(trace.overwritten_events == 2U);
    for (size_t i = 0U; i < count; i++) {
        assert(out[i].sequence == i + 3U);
        assert(out[i].arg0 == (int32_t) i + 3);
        assert(out[i].arg1 == -((int32_t) i + 3));
    }
}

static void test_paged_copy_has_stable_sequence_cursor(void)
{
    blackbox_trace_event_t storage[8];
    blackbox_trace_event_t out[2];
    blackbox_trace_t trace;
    blackbox_trace_init(&trace, storage, 8U);
    blackbox_trace_start(&trace, 0U, 100U);

    for (int32_t i = 0; i < 5; i++) {
        assert(blackbox_trace_record(&trace, (uint64_t) i, 9U, 0U, i, 0));
    }

    uint32_t cursor = 0U;
    size_t total = 0U;
    while (true) {
        uint32_t next = 0U;
        size_t count = blackbox_trace_copy(&trace, cursor, out, 2U, NULL, &next, NULL);
        if (count == 0U) {
            assert(cursor == next);
            break;
        }
        for (size_t i = 0U; i < count; i++) {
            assert(out[i].arg0 == (int32_t) total);
            total++;
        }
        cursor = out[count - 1U].sequence + 1U;
    }
    assert(total == 5U);
}

static void test_wire_capacity_never_exceeds_negotiated_payload(void)
{
    size_t trace_capacity = blackbox_wire_item_capacity(182U, 20U, 20U, 20U);
    size_t counter_capacity = blackbox_wire_item_capacity(182U, 52U, 4U, 39U);
    assert(trace_capacity == 8U);
    assert(20U + (trace_capacity * 20U) <= 182U);
    assert(counter_capacity == 32U);
    assert(52U + (counter_capacity * 4U) <= 182U);
    assert(blackbox_wire_item_capacity(39U, 20U, 20U, 20U) == 0U);
    assert(blackbox_wire_item_capacity(100U, 20U, 0U, 20U) == 0U);
}

static void test_rate_limit_keeps_first_boundary_and_wraparound_events(void)
{
    bool seen = false;
    uint32_t last_ms = 0U;

    assert(blackbox_trace_rate_limit(100U, 1000U, &seen, &last_ms));
    assert(!blackbox_trace_rate_limit(1099U, 1000U, &seen, &last_ms));
    assert(blackbox_trace_rate_limit(1100U, 1000U, &seen, &last_ms));

    seen = true;
    last_ms = UINT32_MAX - 499U;
    assert(!blackbox_trace_rate_limit(499U, 1000U, &seen, &last_ms));
    assert(blackbox_trace_rate_limit(500U, 1000U, &seen, &last_ms));
}

int main(void)
{
    test_trace_expires_without_accepting_late_event();
    test_wrap_reports_cursor_loss_and_preserves_order();
    test_paged_copy_has_stable_sequence_cursor();
    test_wire_capacity_never_exceeds_negotiated_payload();
    test_rate_limit_keeps_first_boundary_and_wraparound_events();
    puts("blackbox trace tests passed");
    return 0;
}
