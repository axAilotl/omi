#ifndef BLACKBOX_TRACE_H
#define BLACKBOX_TRACE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct {
    uint32_t sequence;
    uint32_t uptime_ms;
    uint16_t event;
    uint16_t flags;
    int32_t arg0;
    int32_t arg1;
} blackbox_trace_event_t;

typedef struct {
    blackbox_trace_event_t *events;
    size_t capacity;
    size_t count;
    size_t head;
    uint32_t next_sequence;
    uint32_t overwritten_events;
    uint64_t deadline_ms;
    bool enabled;
} blackbox_trace_t;

void blackbox_trace_init(blackbox_trace_t *trace, blackbox_trace_event_t *events, size_t capacity);
void blackbox_trace_start(blackbox_trace_t *trace, uint64_t now_ms, uint32_t ttl_seconds);
void blackbox_trace_stop(blackbox_trace_t *trace);
void blackbox_trace_clear(blackbox_trace_t *trace);
bool blackbox_trace_record(blackbox_trace_t *trace,
                           uint64_t now_ms,
                           uint16_t event,
                           uint16_t flags,
                           int32_t arg0,
                           int32_t arg1);
size_t blackbox_trace_copy(const blackbox_trace_t *trace,
                           uint32_t requested_sequence,
                           blackbox_trace_event_t *out,
                           size_t out_capacity,
                           uint32_t *oldest_sequence,
                           uint32_t *next_sequence,
                           bool *cursor_overwritten);
size_t blackbox_wire_item_capacity(size_t payload_limit, size_t header_size, size_t item_size, size_t maximum_items);
bool blackbox_trace_rate_limit(uint32_t now_ms, uint32_t min_interval_ms, bool *seen, uint32_t *last_ms);

#endif // BLACKBOX_TRACE_H
