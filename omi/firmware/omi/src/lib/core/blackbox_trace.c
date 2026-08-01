#include "blackbox_trace.h"

#include <string.h>

void blackbox_trace_init(blackbox_trace_t *trace, blackbox_trace_event_t *events, size_t capacity)
{
    memset(trace, 0, sizeof(*trace));
    trace->events = events;
    trace->capacity = capacity;
    trace->next_sequence = 1U;
}

void blackbox_trace_start(blackbox_trace_t *trace, uint64_t now_ms, uint32_t ttl_seconds)
{
    trace->enabled = true;
    trace->deadline_ms = ttl_seconds == 0U ? UINT64_MAX : now_ms + ((uint64_t) ttl_seconds * 1000U);
}

void blackbox_trace_stop(blackbox_trace_t *trace)
{
    trace->enabled = false;
}

void blackbox_trace_clear(blackbox_trace_t *trace)
{
    trace->count = 0U;
    trace->head = 0U;
    trace->overwritten_events = 0U;
}

bool blackbox_trace_record(blackbox_trace_t *trace,
                           uint64_t now_ms,
                           uint16_t event,
                           uint16_t flags,
                           int32_t arg0,
                           int32_t arg1)
{
    if (!trace->enabled || trace->capacity == 0U) {
        return false;
    }
    if (now_ms >= trace->deadline_ms) {
        trace->enabled = false;
        return false;
    }

    size_t index;
    if (trace->count < trace->capacity) {
        index = (trace->head + trace->count) % trace->capacity;
        trace->count++;
    } else {
        index = trace->head;
        trace->head = (trace->head + 1U) % trace->capacity;
        trace->overwritten_events++;
    }

    trace->events[index] = (blackbox_trace_event_t) {
        .sequence = trace->next_sequence++,
        .uptime_ms = (uint32_t) now_ms,
        .event = event,
        .flags = flags,
        .arg0 = arg0,
        .arg1 = arg1,
    };
    return true;
}

size_t blackbox_trace_copy(const blackbox_trace_t *trace,
                           uint32_t requested_sequence,
                           blackbox_trace_event_t *out,
                           size_t out_capacity,
                           uint32_t *oldest_sequence,
                           uint32_t *next_sequence,
                           bool *cursor_overwritten)
{
    uint32_t oldest = trace->count == 0U ? trace->next_sequence : trace->events[trace->head].sequence;
    uint32_t cursor = requested_sequence == 0U ? oldest : requested_sequence;
    bool overwritten = cursor < oldest;
    if (overwritten) {
        cursor = oldest;
    }

    size_t copied = 0U;
    for (size_t i = 0U; i < trace->count && copied < out_capacity; i++) {
        const blackbox_trace_event_t *candidate = &trace->events[(trace->head + i) % trace->capacity];
        if (candidate->sequence >= cursor) {
            out[copied++] = *candidate;
        }
    }

    if (oldest_sequence) {
        *oldest_sequence = oldest;
    }
    if (next_sequence) {
        *next_sequence = trace->next_sequence;
    }
    if (cursor_overwritten) {
        *cursor_overwritten = overwritten;
    }
    return copied;
}

size_t blackbox_wire_item_capacity(size_t payload_limit, size_t header_size, size_t item_size, size_t maximum_items)
{
    if (payload_limit < header_size || item_size == 0U) {
        return 0U;
    }
    size_t capacity = (payload_limit - header_size) / item_size;
    return capacity < maximum_items ? capacity : maximum_items;
}

bool blackbox_trace_rate_limit(uint32_t now_ms, uint32_t min_interval_ms, bool *seen, uint32_t *last_ms)
{
    if (!*seen || (uint32_t) (now_ms - *last_ms) >= min_interval_ms) {
        *seen = true;
        *last_ms = now_ms;
        return true;
    }
    return false;
}
