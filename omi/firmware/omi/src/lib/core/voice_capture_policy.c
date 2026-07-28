#include "voice_capture_policy.h"

#include <stddef.h>

voice_capture_policy_result_t voice_capture_policy_process(voice_activity_gate_t *gate,
                                                           uint32_t average_absolute_amplitude,
                                                           int64_t now_ms,
                                                           const voice_activity_gate_config_t *config,
                                                           voice_capture_forward_t forward,
                                                           void *context)
{
    voice_capture_policy_result_t result = {
        .gate_action = voice_activity_gate_process(gate, average_absolute_amplitude, now_ms, config),
        .forwarded = false,
    };

    /*
     * The software gate informs only the hardware-AAD hold policy. While PDM
     * is awake, every captured frame must cross the codec/storage boundary.
     */
    if (forward) {
        result.forwarded = forward(context);
    }
    return result;
}
