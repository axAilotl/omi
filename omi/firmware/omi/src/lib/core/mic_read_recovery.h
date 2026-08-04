#ifndef MIC_READ_RECOVERY_H
#define MIC_READ_RECOVERY_H

#include <stdbool.h>

typedef enum {
    MIC_READ_RECOVERY_NONE = 0,
    MIC_READ_RECOVERY_START,
} mic_read_recovery_action_t;

mic_read_recovery_action_t mic_read_recovery_action(int read_result, bool stop_requested);

#endif // MIC_READ_RECOVERY_H
