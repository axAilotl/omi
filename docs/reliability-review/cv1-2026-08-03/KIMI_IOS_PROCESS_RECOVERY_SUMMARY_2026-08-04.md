# Kimi follow-up: iOS process-death recovery

Date: 2026-08-04 UTC
Reviewer: Kimi Code on the independent Linux review host
Scope: analysis only; no code modified

The complete raw review remains on the review host at:

```text
/mnt/ai/omi-cv1-ios-process-recovery-2026-08-04/
KIMI_IOS_PROCESS_RECOVERY_REVIEW.md
```

Kimi session identifier:
`session_4e774221-7412-4d44-b866-56fa68d49b1e`

## Verdict

The observed process-death conversation split is primarily **app-side**, with a
secondary backend lifecycle race. No new firmware change is required for this
incident class.

## App-side ownership race

1. `ConversationSessionWindow` and `_activeConversationId` are in memory only.
   Process death destroys the conversation start/owner while audio WALs remain
   durable.
2. `_reclaimInProgressConversationBeforeSocket()` is a single-shot fetch. A
   cold-start auth/network failure fails open and allows an ownerless socket.
3. Without reclaim, the app starts its window at relaunch time. The server's
   `ConversationSessionEvent` does not include authoritative `started_at`, so a
   later event cannot rewind the window.
4. `stampConversationId()` correctly applies the bounded session window, but
   the incorrect relaunch boundary excludes outage WALs. In the reviewed trace,
   the newest excluded WAL ended only about three seconds before the new
   boundary.
5. Unbound storage-continuity WALs are correctly excluded from independent
   upload. That protects the server from tiny-file spam but makes the bad owner
   decision permanent.

Kimi confirmed that the audio was durable on the phone and pendant; the defect
is binding/ownership, not transport loss.

## Backend contribution

The backend appears to have resumed the pre-death conversation because the
reconnect occurred inside the 120-second boundary. Its inactivity clock was not
reset on resume. The resumed conversation could therefore be processed about
31 seconds after relaunch when the old `finished_at + 120 s` boundary expired,
even though post-reconnect audio was streaming.

## Smallest recommended split

App:

- persist a boundary-validated session-window checkpoint;
- restore it before opening the first socket;
- retry a failed in-progress-conversation fetch with bounded backoff;
- on terminal fetch uncertainty, retain the valid checkpoint rather than
  pinning to relaunch time.

Backend:

- add authoritative `started_at` (and preferably `finished_at`) to the session
  event;
- refresh the lifecycle activity clock once when resuming a conversation.

Do not loosen the raw-fragment upload guard or the bounded session gate. Those
are correct given a correct owner and boundary. Do not append blindly to an
already-materialized canonical because its source proof has been discarded and
that can duplicate or erase audio.

## Final physical-pass nits

Kimi recommended three bounded checks for the final iPhone pass:

1. after drain, verify no source range is both bound into a live canonical and
   compacted into a historical archive;
2. correlate any UI freeze with GATT bursts or WAL manifest writes while
   measuring preview latency, not just eventual text;
3. audit short WALs at the power-cycle boundary and confirm ring recovery starts
   at the live head without replaying already-synced ranges.

All three are app-side checks. Firmware connect/disconnect counters are useful
only as corroboration. Kimi's final recommendation after the no-tap +5/+15
preview evidence was **go**, with a freeze during sync treated as the condition
that would flip the result to stop.
