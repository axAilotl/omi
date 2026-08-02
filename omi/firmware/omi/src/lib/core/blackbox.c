#include "blackbox.h"

#include <errno.h>
#include <string.h>
#include <zephyr/bluetooth/gatt.h>
#include <zephyr/bluetooth/uuid.h>
#include <zephyr/kernel.h>
#include <zephyr/sys/atomic.h>
#include <zephyr/sys/byteorder.h>
#include <zephyr/sys/util.h>

#include "blackbox_trace.h"

#define BLACKBOX_PROTOCOL_VERSION 1U
#define BLACKBOX_TRACE_CAPACITY 512U
#define BLACKBOX_TRACE_DEFAULT_TTL_SECONDS (12U * 60U * 60U)
#define BLACKBOX_TRACE_MAX_TTL_SECONDS (24U * 60U * 60U)
#define BLACKBOX_TRACE_EVENTS_PER_RESPONSE 20U
#define BLACKBOX_TRACE_EVENT_WIRE_SIZE 20U
#define BLACKBOX_SNAPSHOT_HEADER_SIZE 52U
#define BLACKBOX_RESPONSE_MAX_SIZE 480U

#define BLACKBOX_COMMAND_SNAPSHOT 0x01U
#define BLACKBOX_COMMAND_START_TRACE 0x02U
#define BLACKBOX_COMMAND_STOP_TRACE 0x03U
#define BLACKBOX_COMMAND_READ_TRACE 0x04U
#define BLACKBOX_COMMAND_CLEAR_TRACE 0x05U

#define BLACKBOX_RESPONSE_ACK 0x80U
#define BLACKBOX_RESPONSE_SNAPSHOT 0x81U
#define BLACKBOX_RESPONSE_TRACE 0x82U

#define BLACKBOX_TRACE_FLAG_ENABLED BIT(0)
#define BLACKBOX_SNAPSHOT_FLAG_MORE_COUNTERS BIT(1)
#define BLACKBOX_TRACE_PAGE_FLAG_MORE BIT(0)
#define BLACKBOX_TRACE_PAGE_FLAG_CURSOR_OVERWRITTEN BIT(1)

struct blackbox_runtime_state {
    uint32_t reset_reason;
    uint32_t boot_count;
    uint16_t connection_interval;
    uint16_t connection_latency;
    uint16_t supervision_timeout;
    uint16_t mtu;
    uint16_t tx_data_length;
    uint16_t rx_data_length;
    uint16_t battery_millivolts;
    uint8_t tx_phy;
    uint8_t rx_phy;
    uint8_t battery_percentage;
    uint8_t charging;
    uint8_t sd_powered;
    uint8_t sd_ready;
    uint8_t sd_health;
};

static atomic_t counters[BLACKBOX_COUNTER_COUNT];
static struct blackbox_runtime_state runtime_state;
static blackbox_trace_event_t trace_storage[BLACKBOX_TRACE_CAPACITY];
static blackbox_trace_t trace;
static struct k_spinlock state_lock;
static atomic_t response_in_flight;
static uint8_t response_buffer[BLACKBOX_RESPONSE_MAX_SIZE];
static uint32_t event_last_ms[BLACKBOX_EVENT_COUNT];
static bool event_seen[BLACKBOX_EVENT_COUNT];

static ssize_t blackbox_command_write(struct bt_conn *conn,
                                      const struct bt_gatt_attr *attr,
                                      const void *buf,
                                      uint16_t len,
                                      uint16_t offset,
                                      uint8_t flags);
static void blackbox_ccc_changed(const struct bt_gatt_attr *attr, uint16_t value);

static struct bt_uuid_128 blackbox_service_uuid =
    BT_UUID_INIT_128(BT_UUID_128_ENCODE(0x30295790, 0x4301, 0xEABD, 0x2904, 0x2849ADFEAE43));
static struct bt_uuid_128 blackbox_command_uuid =
    BT_UUID_INIT_128(BT_UUID_128_ENCODE(0x30295791, 0x4301, 0xEABD, 0x2904, 0x2849ADFEAE43));

static struct bt_gatt_attr blackbox_service_attrs[] = {
    BT_GATT_PRIMARY_SERVICE(&blackbox_service_uuid),
    BT_GATT_CHARACTERISTIC(&blackbox_command_uuid.uuid,
                           BT_GATT_CHRC_WRITE | BT_GATT_CHRC_NOTIFY,
                           BT_GATT_PERM_WRITE,
                           NULL,
                           blackbox_command_write,
                           NULL),
    BT_GATT_CCC(blackbox_ccc_changed, BT_GATT_PERM_READ | BT_GATT_PERM_WRITE),
};

static struct bt_gatt_service blackbox_service = BT_GATT_SERVICE(blackbox_service_attrs);

BUILD_ASSERT(BLACKBOX_RESPONSE_MAX_SIZE >=
                 (20U + (BLACKBOX_TRACE_EVENTS_PER_RESPONSE * BLACKBOX_TRACE_EVENT_WIRE_SIZE)),
             "blackbox trace response buffer too small");

static uint64_t blackbox_now_ms(void)
{
    return (uint64_t) k_uptime_get();
}

static void expire_trace_if_needed_locked(uint64_t now_ms)
{
    if (trace.enabled && now_ms >= trace.deadline_ms) {
        blackbox_trace_stop(&trace);
    }
}

static void response_complete(struct bt_conn *conn, void *user_data)
{
    ARG_UNUSED(conn);
    ARG_UNUSED(user_data);
    atomic_clear(&response_in_flight);
}

static int notify_response(struct bt_conn *conn, uint16_t response_len)
{
    struct bt_gatt_notify_params params = {
        .attr = &blackbox_service.attrs[2],
        .data = response_buffer,
        .len = response_len,
        .func = response_complete,
        .user_data = NULL,
    };

    int err = bt_gatt_notify_cb(conn, &params);
    if (err != 0) {
        atomic_clear(&response_in_flight);
    }
    return err;
}

static uint16_t build_ack(uint8_t command, int8_t status)
{
    uint32_t next_sequence;
    bool enabled;
    k_spinlock_key_t key = k_spin_lock(&state_lock);
    expire_trace_if_needed_locked(blackbox_now_ms());
    next_sequence = trace.next_sequence;
    enabled = trace.enabled;
    k_spin_unlock(&state_lock, key);

    response_buffer[0] = BLACKBOX_RESPONSE_ACK;
    response_buffer[1] = BLACKBOX_PROTOCOL_VERSION;
    response_buffer[2] = command;
    response_buffer[3] = (uint8_t) status;
    response_buffer[4] = enabled ? BLACKBOX_TRACE_FLAG_ENABLED : 0U;
    response_buffer[5] = 0U;
    response_buffer[6] = 0U;
    response_buffer[7] = 0U;
    sys_put_le32(next_sequence, &response_buffer[8]);
    return 12U;
}

static uint16_t build_snapshot(uint8_t counter_start, uint16_t payload_limit)
{
    struct blackbox_runtime_state state;
    uint32_t oldest_sequence;
    uint32_t next_sequence;
    uint32_t overwritten_events;
    uint16_t trace_count;
    bool enabled;

    k_spinlock_key_t key = k_spin_lock(&state_lock);
    expire_trace_if_needed_locked(blackbox_now_ms());
    state = runtime_state;
    (void) blackbox_trace_copy(&trace, 0U, NULL, 0U, &oldest_sequence, &next_sequence, NULL);
    overwritten_events = trace.overwritten_events;
    trace_count = (uint16_t) trace.count;
    enabled = trace.enabled;
    k_spin_unlock(&state_lock, key);

    uint8_t available_counters = (uint8_t) blackbox_wire_item_capacity(
        payload_limit, BLACKBOX_SNAPSHOT_HEADER_SIZE, sizeof(uint32_t), BLACKBOX_COUNTER_COUNT);
    uint8_t remaining_counters = BLACKBOX_COUNTER_COUNT - counter_start;
    uint8_t counter_count = MIN(available_counters, remaining_counters);

    response_buffer[0] = BLACKBOX_RESPONSE_SNAPSHOT;
    response_buffer[1] = BLACKBOX_PROTOCOL_VERSION;
    response_buffer[2] = enabled ? BLACKBOX_TRACE_FLAG_ENABLED : 0U;
    if ((uint8_t) (counter_start + counter_count) < BLACKBOX_COUNTER_COUNT) {
        response_buffer[2] |= BLACKBOX_SNAPSHOT_FLAG_MORE_COUNTERS;
    }
    response_buffer[3] = counter_count;
    sys_put_le32(state.boot_count, &response_buffer[4]);
    sys_put_le32(state.reset_reason, &response_buffer[8]);
    sys_put_le32((uint32_t) blackbox_now_ms(), &response_buffer[12]);
    sys_put_le32(oldest_sequence, &response_buffer[16]);
    sys_put_le32(next_sequence, &response_buffer[20]);
    sys_put_le32(overwritten_events, &response_buffer[24]);
    sys_put_le16(trace_count, &response_buffer[28]);
    sys_put_le16(state.connection_interval, &response_buffer[30]);
    sys_put_le16(state.connection_latency, &response_buffer[32]);
    sys_put_le16(state.supervision_timeout, &response_buffer[34]);
    sys_put_le16(state.mtu, &response_buffer[36]);
    sys_put_le16(state.tx_data_length, &response_buffer[38]);
    sys_put_le16(state.rx_data_length, &response_buffer[40]);
    response_buffer[42] = state.tx_phy;
    response_buffer[43] = state.rx_phy;
    sys_put_le16(state.battery_millivolts, &response_buffer[44]);
    response_buffer[46] = state.battery_percentage;
    response_buffer[47] = state.charging;
    response_buffer[48] = state.sd_powered;
    response_buffer[49] = state.sd_ready;
    response_buffer[50] = state.sd_health;
    response_buffer[51] = counter_start;

    for (uint8_t i = 0U; i < counter_count; i++) {
        sys_put_le32((uint32_t) atomic_get(&counters[counter_start + i]),
                     &response_buffer[BLACKBOX_SNAPSHOT_HEADER_SIZE + ((uint16_t) i * sizeof(uint32_t))]);
    }
    return BLACKBOX_SNAPSHOT_HEADER_SIZE + ((uint16_t) counter_count * sizeof(uint32_t));
}

static uint16_t build_trace_page(uint32_t requested_sequence, uint16_t payload_limit)
{
    blackbox_trace_event_t events[BLACKBOX_TRACE_EVENTS_PER_RESPONSE];
    uint32_t oldest_sequence;
    uint32_t global_next_sequence;
    uint32_t overwritten_events;
    bool cursor_overwritten;
    size_t count;

    k_spinlock_key_t key = k_spin_lock(&state_lock);
    expire_trace_if_needed_locked(blackbox_now_ms());
    size_t event_capacity = blackbox_wire_item_capacity(
        payload_limit, 20U, BLACKBOX_TRACE_EVENT_WIRE_SIZE, BLACKBOX_TRACE_EVENTS_PER_RESPONSE);
    count = blackbox_trace_copy(&trace,
                                requested_sequence,
                                events,
                                event_capacity,
                                &oldest_sequence,
                                &global_next_sequence,
                                &cursor_overwritten);
    overwritten_events = trace.overwritten_events;
    k_spin_unlock(&state_lock, key);

    uint32_t page_next_sequence = count == 0U ? global_next_sequence : events[count - 1U].sequence + 1U;
    uint8_t page_flags = 0U;
    if (page_next_sequence < global_next_sequence) {
        page_flags |= BLACKBOX_TRACE_PAGE_FLAG_MORE;
    }
    if (cursor_overwritten) {
        page_flags |= BLACKBOX_TRACE_PAGE_FLAG_CURSOR_OVERWRITTEN;
    }

    response_buffer[0] = BLACKBOX_RESPONSE_TRACE;
    response_buffer[1] = BLACKBOX_PROTOCOL_VERSION;
    response_buffer[2] = (uint8_t) count;
    response_buffer[3] = page_flags;
    sys_put_le32(oldest_sequence, &response_buffer[4]);
    sys_put_le32(page_next_sequence, &response_buffer[8]);
    sys_put_le32(global_next_sequence, &response_buffer[12]);
    sys_put_le32(overwritten_events, &response_buffer[16]);

    for (size_t i = 0U; i < count; i++) {
        uint16_t offset = 20U + ((uint16_t) i * BLACKBOX_TRACE_EVENT_WIRE_SIZE);
        sys_put_le32(events[i].sequence, &response_buffer[offset]);
        sys_put_le32(events[i].uptime_ms, &response_buffer[offset + 4U]);
        sys_put_le16(events[i].event, &response_buffer[offset + 8U]);
        sys_put_le16(events[i].flags, &response_buffer[offset + 10U]);
        sys_put_le32((uint32_t) events[i].arg0, &response_buffer[offset + 12U]);
        sys_put_le32((uint32_t) events[i].arg1, &response_buffer[offset + 16U]);
    }
    return 20U + ((uint16_t) count * BLACKBOX_TRACE_EVENT_WIRE_SIZE);
}

static ssize_t blackbox_command_write(struct bt_conn *conn,
                                      const struct bt_gatt_attr *attr,
                                      const void *buf,
                                      uint16_t len,
                                      uint16_t offset,
                                      uint8_t flags)
{
    ARG_UNUSED(attr);
    ARG_UNUSED(flags);

    if (offset != 0U || len < 1U) {
        return BT_GATT_ERR(BT_ATT_ERR_INVALID_ATTRIBUTE_LEN);
    }
    if (!bt_gatt_is_subscribed(conn, &blackbox_service.attrs[2], BT_GATT_CCC_NOTIFY)) {
        return BT_GATT_ERR(BT_ATT_ERR_CCC_IMPROPER_CONF);
    }
    if (!atomic_cas(&response_in_flight, 0, 1)) {
        blackbox_counter_add(BLACKBOX_COUNTER_DIAGNOSTIC_BUSY, 1U);
        return BT_GATT_ERR(BT_ATT_ERR_INSUFFICIENT_RESOURCES);
    }

    blackbox_counter_add(BLACKBOX_COUNTER_DIAGNOSTIC_REQUEST, 1U);
    const uint8_t *command_data = buf;
    uint8_t command = command_data[0];
    uint16_t payload_limit = MIN((uint16_t) (bt_gatt_get_mtu(conn) - 3U), (uint16_t) sizeof(response_buffer));
    uint16_t response_len;

    switch (command) {
    case BLACKBOX_COMMAND_SNAPSHOT: {
        uint8_t counter_start = len >= 2U ? command_data[1] : 0U;
        if (counter_start >= BLACKBOX_COUNTER_COUNT ||
            payload_limit < (BLACKBOX_SNAPSHOT_HEADER_SIZE + sizeof(uint32_t))) {
            atomic_clear(&response_in_flight);
            return BT_GATT_ERR(BT_ATT_ERR_INVALID_ATTRIBUTE_LEN);
        }
        response_len = build_snapshot(counter_start, payload_limit);
        break;
    }
    case BLACKBOX_COMMAND_START_TRACE: {
        uint32_t ttl_seconds = len >= 5U ? sys_get_le32(&command_data[1]) : BLACKBOX_TRACE_DEFAULT_TTL_SECONDS;
        ttl_seconds = CLAMP(ttl_seconds, 1U, BLACKBOX_TRACE_MAX_TTL_SECONDS);
        k_spinlock_key_t key = k_spin_lock(&state_lock);
        memset(event_last_ms, 0, sizeof(event_last_ms));
        memset(event_seen, 0, sizeof(event_seen));
        blackbox_trace_start(&trace, blackbox_now_ms(), ttl_seconds);
        (void) blackbox_trace_record(
            &trace, blackbox_now_ms(), BLACKBOX_EVENT_TRACE_STARTED, 0U, (int32_t) ttl_seconds, 0);
        k_spin_unlock(&state_lock, key);
        response_len = build_ack(command, 0);
        break;
    }
    case BLACKBOX_COMMAND_STOP_TRACE: {
        blackbox_record(BLACKBOX_EVENT_TRACE_STOPPED, 0, 0);
        k_spinlock_key_t key = k_spin_lock(&state_lock);
        blackbox_trace_stop(&trace);
        k_spin_unlock(&state_lock, key);
        response_len = build_ack(command, 0);
        break;
    }
    case BLACKBOX_COMMAND_READ_TRACE: {
        if (payload_limit < (20U + BLACKBOX_TRACE_EVENT_WIRE_SIZE)) {
            atomic_clear(&response_in_flight);
            return BT_GATT_ERR(BT_ATT_ERR_INVALID_ATTRIBUTE_LEN);
        }
        uint32_t sequence = len >= 5U ? sys_get_le32(&command_data[1]) : 0U;
        response_len = build_trace_page(sequence, payload_limit);
        break;
    }
    case BLACKBOX_COMMAND_CLEAR_TRACE: {
        k_spinlock_key_t key = k_spin_lock(&state_lock);
        blackbox_trace_clear(&trace);
        memset(event_last_ms, 0, sizeof(event_last_ms));
        memset(event_seen, 0, sizeof(event_seen));
        k_spin_unlock(&state_lock, key);
        response_len = build_ack(command, 0);
        break;
    }
    default:
        response_len = build_ack(command, -1);
        break;
    }

    int err = notify_response(conn, response_len);
    if (err != 0) {
        return BT_GATT_ERR(BT_ATT_ERR_UNLIKELY);
    }
    return len;
}

static void blackbox_ccc_changed(const struct bt_gatt_attr *attr, uint16_t value)
{
    ARG_UNUSED(attr);
    ARG_UNUSED(value);
}

int blackbox_init(uint32_t reset_reason, uint32_t boot_count)
{
    memset(&runtime_state, 0, sizeof(runtime_state));
    for (uint8_t i = 0U; i < BLACKBOX_COUNTER_COUNT; i++) {
        atomic_clear(&counters[i]);
    }
    atomic_clear(&response_in_flight);
    memset(event_last_ms, 0, sizeof(event_last_ms));
    memset(event_seen, 0, sizeof(event_seen));
    blackbox_trace_init(&trace, trace_storage, ARRAY_SIZE(trace_storage));
    runtime_state.reset_reason = reset_reason;
    runtime_state.boot_count = boot_count;
    blackbox_trace_start(&trace, blackbox_now_ms(), BLACKBOX_TRACE_DEFAULT_TTL_SECONDS);
    blackbox_counter_add(BLACKBOX_COUNTER_BOOT, 1U);
    blackbox_record(BLACKBOX_EVENT_BOOT, (int32_t) reset_reason, (int32_t) boot_count);
    return 0;
}

int blackbox_register_service(void)
{
    return bt_gatt_service_register(&blackbox_service);
}

void blackbox_counter_add(enum blackbox_counter counter, uint32_t amount)
{
    if ((unsigned int) counter >= BLACKBOX_COUNTER_COUNT) {
        return;
    }
    atomic_add(&counters[counter], (atomic_val_t) amount);
}

void blackbox_record(enum blackbox_event event, int32_t arg0, int32_t arg1)
{
    k_spinlock_key_t key = k_spin_lock(&state_lock);
    (void) blackbox_trace_record(&trace, blackbox_now_ms(), (uint16_t) event, 0U, arg0, arg1);
    k_spin_unlock(&state_lock, key);
}

void blackbox_record_rate_limited(enum blackbox_event event, int32_t arg0, int32_t arg1, uint32_t min_interval_ms)
{
    if ((unsigned int) event >= BLACKBOX_EVENT_COUNT) {
        return;
    }
    uint32_t now_ms = (uint32_t) blackbox_now_ms();
    k_spinlock_key_t key = k_spin_lock(&state_lock);
    if (blackbox_trace_rate_limit(now_ms, min_interval_ms, &event_seen[event], &event_last_ms[event])) {
        (void) blackbox_trace_record(&trace, now_ms, (uint16_t) event, 0U, arg0, arg1);
    }
    k_spin_unlock(&state_lock, key);
}

void blackbox_set_link_params(uint16_t interval, uint16_t latency, uint16_t timeout)
{
    k_spinlock_key_t key = k_spin_lock(&state_lock);
    runtime_state.connection_interval = interval;
    runtime_state.connection_latency = latency;
    runtime_state.supervision_timeout = timeout;
    k_spin_unlock(&state_lock, key);
}

void blackbox_set_phy(uint8_t tx_phy, uint8_t rx_phy)
{
    k_spinlock_key_t key = k_spin_lock(&state_lock);
    runtime_state.tx_phy = tx_phy;
    runtime_state.rx_phy = rx_phy;
    k_spin_unlock(&state_lock, key);
}

void blackbox_set_data_length(uint16_t tx_length, uint16_t rx_length)
{
    k_spinlock_key_t key = k_spin_lock(&state_lock);
    runtime_state.tx_data_length = tx_length;
    runtime_state.rx_data_length = rx_length;
    k_spin_unlock(&state_lock, key);
}

void blackbox_set_mtu(uint16_t mtu)
{
    k_spinlock_key_t key = k_spin_lock(&state_lock);
    runtime_state.mtu = mtu;
    k_spin_unlock(&state_lock, key);
}

void blackbox_set_battery(uint16_t millivolts, uint8_t percentage, bool charging)
{
    k_spinlock_key_t key = k_spin_lock(&state_lock);
    runtime_state.battery_millivolts = millivolts;
    runtime_state.battery_percentage = percentage;
    runtime_state.charging = charging ? 1U : 0U;
    k_spin_unlock(&state_lock, key);
}

void blackbox_set_sd_state(bool powered, bool ready, uint8_t health)
{
    k_spinlock_key_t key = k_spin_lock(&state_lock);
    runtime_state.sd_powered = powered ? 1U : 0U;
    runtime_state.sd_ready = ready ? 1U : 0U;
    runtime_state.sd_health = health;
    k_spin_unlock(&state_lock, key);
}
