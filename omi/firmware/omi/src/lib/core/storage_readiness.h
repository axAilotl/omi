#ifndef STORAGE_READINESS_H
#define STORAGE_READINESS_H

#include <stdbool.h>

typedef enum {
    STORAGE_READINESS_SERVE = 0,
    STORAGE_READINESS_SERVE_DURABLE_PREFIX,
    STORAGE_READINESS_WAKE_AND_WAIT,
    STORAGE_READINESS_WAIT,
    STORAGE_READINESS_RETRYABLE_TIMEOUT,
    STORAGE_READINESS_TERMINAL,
} storage_readiness_action_t;

/**
 * Decide how a pending ring INFO/READ command should progress.
 *
 * A mounted card always has a safe durable prefix that the SD worker can
 * snapshot. The pusher's connect-time partial-tail flush improves freshness,
 * but must never gate access to records that are already durable: continuous
 * capture or SD backpressure can delay that flush indefinitely.
 *
 * The policy is platform-free so the real firmware state machine can be
 * exhaustively tested without a live SD controller or Bluetooth stack.
 */
storage_readiness_action_t storage_readiness_decide(bool media_ready,
                                                    bool snapshot_ready,
                                                    bool storage_terminal,
                                                    bool deadline_started,
                                                    bool deadline_expired);

#endif
