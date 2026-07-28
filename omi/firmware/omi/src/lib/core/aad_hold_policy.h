#ifndef AAD_HOLD_POLICY_H
#define AAD_HOLD_POLICY_H

#include <stdbool.h>
#include <stdint.h>

#include "voice_activity_gate.h"

typedef struct {
    bool conversation_active;
    int64_t last_activity_ms;
} aad_hold_policy_t;

void aad_hold_policy_init(aad_hold_policy_t *policy, int64_t now_ms);

void aad_hold_policy_reset_after_wake(aad_hold_policy_t *policy, int64_t now_ms);

void aad_hold_policy_refresh_activity(aad_hold_policy_t *policy, int64_t now_ms);

void aad_hold_policy_track_voice_gate(aad_hold_policy_t *policy, const voice_activity_gate_t *gate, int64_t now_ms);

uint32_t
aad_hold_policy_current_hold_ms(const aad_hold_policy_t *policy, uint32_t idle_hold_ms, uint32_t conversation_hold_ms);

bool aad_hold_policy_sleep_due(const aad_hold_policy_t *policy,
                               int64_t now_ms,
                               uint32_t idle_hold_ms,
                               uint32_t conversation_hold_ms);

#endif
