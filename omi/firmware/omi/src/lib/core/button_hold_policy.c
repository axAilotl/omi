#include "button_hold_policy.h"

#include <stddef.h>

void button_hold_policy_init(button_hold_policy_t *policy)
{
    if (policy == NULL) {
        return;
    }

    *policy = (button_hold_policy_t) {0};
}

button_hold_action_t button_hold_policy_update(button_hold_policy_t *policy, bool pressed, int64_t now_ms)
{
    if (policy == NULL) {
        return BUTTON_HOLD_ACTION_NONE;
    }

    if (!pressed) {
        button_hold_policy_init(policy);
        return BUTTON_HOLD_ACTION_NONE;
    }

    if (!policy->pressed) {
        policy->pressed = true;
        policy->pressed_at_ms = now_ms;
        return BUTTON_HOLD_ACTION_NONE;
    }

    /* A clock regression cannot manufacture a long hold. */
    int64_t elapsed_ms = now_ms >= policy->pressed_at_ms ? now_ms - policy->pressed_at_ms : 0;

    if (!policy->emergency_reboot_issued && elapsed_ms >= BUTTON_HOLD_EMERGENCY_REBOOT_MS) {
        policy->emergency_reboot_issued = true;
        return BUTTON_HOLD_ACTION_EMERGENCY_REBOOT;
    }

    if (!policy->graceful_shutdown_issued && elapsed_ms >= BUTTON_HOLD_GRACEFUL_SHUTDOWN_MS) {
        policy->graceful_shutdown_issued = true;
        return BUTTON_HOLD_ACTION_GRACEFUL_SHUTDOWN;
    }

    return BUTTON_HOLD_ACTION_NONE;
}
