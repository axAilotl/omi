#ifndef VOICE_CAPTURE_POLICY_H
#define VOICE_CAPTURE_POLICY_H

#include <stdbool.h>
#include <stdint.h>

#include "voice_activity_gate.h"

typedef bool (*voice_capture_forward_t)(void *context);

typedef struct {
    voice_activity_gate_action_t gate_action;
    bool forwarded;
} voice_capture_policy_result_t;

voice_capture_policy_result_t voice_capture_policy_process(voice_activity_gate_t *gate,
                                                           uint32_t average_absolute_amplitude,
                                                           int64_t now_ms,
                                                           const voice_activity_gate_config_t *config,
                                                           voice_capture_forward_t forward,
                                                           void *context);

#endif
