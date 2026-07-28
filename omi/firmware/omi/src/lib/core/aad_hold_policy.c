#include "aad_hold_policy.h"

#include <stddef.h>

void aad_hold_policy_init(aad_hold_policy_t *policy, int64_t now_ms)
{
    if (!policy) {
        return;
    }

    policy->conversation_active = false;
    policy->last_activity_ms = now_ms;
}

void aad_hold_policy_reset_after_wake(aad_hold_policy_t *policy, int64_t now_ms)
{
    aad_hold_policy_init(policy, now_ms);
}

void aad_hold_policy_refresh_activity(aad_hold_policy_t *policy, int64_t now_ms)
{
    if (!policy) {
        return;
    }

    policy->last_activity_ms = now_ms;
}

void aad_hold_policy_track_voice_gate(aad_hold_policy_t *policy, const voice_activity_gate_t *gate, int64_t now_ms)
{
    if (!policy || !gate) {
        return;
    }

    /*
     * An above-threshold candidate keeps the software detector awake for the
     * short idle window. It becomes a conversation only after the voice gate
     * has satisfied its debounce contract and opened.
     */
    if (gate->frame_active) {
        policy->last_activity_ms = now_ms;
    }
    if (gate->is_open) {
        policy->conversation_active = true;
    }
}

uint32_t
aad_hold_policy_current_hold_ms(const aad_hold_policy_t *policy, uint32_t idle_hold_ms, uint32_t conversation_hold_ms)
{
    if (!policy) {
        return idle_hold_ms;
    }

    return policy->conversation_active ? conversation_hold_ms : idle_hold_ms;
}

bool aad_hold_policy_sleep_due(const aad_hold_policy_t *policy,
                               int64_t now_ms,
                               uint32_t idle_hold_ms,
                               uint32_t conversation_hold_ms)
{
    if (!policy || now_ms < policy->last_activity_ms) {
        return false;
    }

    uint32_t hold_ms = aad_hold_policy_current_hold_ms(policy, idle_hold_ms, conversation_hold_ms);
    return (uint64_t) (now_ms - policy->last_activity_ms) >= hold_ms;
}
