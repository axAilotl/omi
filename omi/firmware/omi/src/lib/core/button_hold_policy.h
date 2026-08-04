#ifndef BUTTON_HOLD_POLICY_H
#define BUTTON_HOLD_POLICY_H

#include <stdbool.h>
#include <stdint.h>

#define BUTTON_HOLD_GRACEFUL_SHUTDOWN_MS 3000LL
#define BUTTON_HOLD_EMERGENCY_REBOOT_MS 30000LL

typedef enum {
    BUTTON_HOLD_ACTION_NONE = 0,
    BUTTON_HOLD_ACTION_GRACEFUL_SHUTDOWN,
    BUTTON_HOLD_ACTION_EMERGENCY_REBOOT,
} button_hold_action_t;

typedef struct {
    int64_t pressed_at_ms;
    bool pressed;
    bool graceful_shutdown_issued;
    bool emergency_reboot_issued;
} button_hold_policy_t;

void button_hold_policy_init(button_hold_policy_t *policy);

button_hold_action_t button_hold_policy_update(button_hold_policy_t *policy, bool pressed, int64_t now_ms);

#endif
