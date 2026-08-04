#include "mic_read_recovery.h"

#include <errno.h>

mic_read_recovery_action_t mic_read_recovery_action(int read_result, bool stop_requested)
{
    if (stop_requested || read_result != -EAGAIN) {
        return MIC_READ_RECOVERY_NONE;
    }

    /*
     * Zephyr's nRF PDM driver stops itself when its slab or RX queue is
     * exhausted. dmic_read() then returns -EAGAIN forever until START is
     * triggered again. START is idempotent while capture is still active, so
     * it is also safe for an isolated read timeout.
     */
    return MIC_READ_RECOVERY_START;
}
