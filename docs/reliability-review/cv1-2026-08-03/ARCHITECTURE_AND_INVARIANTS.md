# Architecture and invariants

## Product objective

The pendant must produce a coherent, chronologically correct conversation even
when BLE, the app process, the transcription socket, or the phone is absent for
part of that conversation. Reliability is not merely moving bytes: the result
must remain playable, transcribable, correctly timed, deduplicated, and
presented as one conversation until the configured silence boundary closes it.

## Authoritative pipeline

```text
microphone -> Opus frame -> pendant SD ring -> phone durable WAL
          -> conversation-bound canonical audio -> backend transcript
          -> conversation/timeline -> derived summary/events
```

Each arrow is a durability boundary. The upstream copy may be acknowledged or
discarded only after the downstream owner has durably accepted the exact source
identity and range.

### Pendant

- The SD ring is the authoritative first copy.
- A frame is ordered and accepted by storage before it is eligible for live
  delivery.
- SD queue pressure cannot allow newer frames to overtake the blocked frame.
- Ring records carry stable sequence identity and capture time.
- A bounded read has an immutable start/count snapshot, a byte CRC, and a DONE
  boundary.
- `ADVANCE` is legal only after the phone durably registers the complete exact
  range.
- BLE disconnect is not a conversation boundary and never authorizes data loss.

### Phone

- The phone durably stores immutable physical ranges as WALs.
- One serial ring reader owns the command/notification protocol.
- The app assembles overlapping/adjacent ranges by exact source identity, not
  by guessing from filenames or arrival order.
- Physical WAL boundaries remain internal. User-visible rows and backend jobs
  represent logical conversation windows.
- Retry reuses the same logical identity and source coverage.
- A missing/corrupt local file is quarantined or truthfully recovered; it does
  not spin forever or cause the pendant cursor to advance.

### Backend

- The accepted canonical artifact owns the final audio/timeline for its source
  coverage.
- Late recovery inside an open conversation is inserted in timestamp order.
- Replacement/merge is atomic and idempotent.
- Derived transcripts, summaries, and events are invalidated/recomputed when
  their source timeline changes.
- Short/noise fragments are not independently summarized merely because a
  storage object exists.

The backend contract is deferred from this firmware/app stabilization phase,
but the app cannot claim final deduplication until the backend implements it.

## Three scheduling lanes

### 1. Live head

The newest bounded records required for current transcription. This lane has
highest priority. It is allowed only when the transcription owner is ready to
consume ordered audio; otherwise the SD ring retains the audio.

### 2. Recent-gap repair

Missing coverage belonging to the still-open conversation. It may run
automatically because it restores current user intent. It must yield to the
live head and preserve the same conversation/preview identity.

### 3. Historical backlog

Older closed conversations. It requires explicit Sync or the existing Auto
Sync opt-in. Charging increases available power but does not grant authority.
Historical work is sliced, resumable, and preemptible by live audio.

If a platform cannot preserve live transcription while draining history, it
must pause historical transfer. Running both lanes is an optimization, not a
correctness requirement.

## Conversation identity and time

- The configured silence timeout (currently treated as approximately two
  minutes) is the semantic close boundary.
- BLE disconnect, WebSocket replacement, app backgrounding, five-minute SD
  archive rotation, upload retry, or phone handoff is not a close boundary.
- Capture wall-clock time and source sequence coverage determine placement.
- Transcript-relative offsets are insufficient after offline gaps because VAD
  and missing transport intervals compress the audio clock.
- Live preview is a projection of the open conversation. Reconnect appends to
  the same owner and preserves existing segments.
- Once canonical recovery changes the accepted timeline, the final transcript
  must use the canonical origin rather than the later live-session origin.

## UI truthfulness

- **Connected** means the exact paired pendant has a usable GATT/audio path.
- **Listening** means the transcription service accepted the session and the
  app is actively feeding ordered audio.
- A physical GATT link alone is not Listening.
- A moving app timer alone is not Listening.
- A frozen SD write cursor while Connected/Listening is a false-ready failure.
- During server recovery, the UI must say that audio is retained/recovering
  rather than presenting a healthy live preview.
- Sync shows logical conversations with playable audio or an explicit reason
  playback is unavailable.

## Cross-platform ownership

Android, iOS, and desktop share the same Dart scheduling, conversation, retry,
and projection policy. Native layers own only transport mechanics:

- session-bound GATT operations;
- notification subscription state;
- stale callback rejection;
- background/restoration ownership;
- exact-device reconnect; and
- DFU suspension/reclaim.

Only one client owns the pendant at a time. An iOS restoration session or
Android background service must release the peripheral when its user-facing
background mode is not authorized.

## VAD and fragment policy

VAD is layered, but each layer has a different job:

1. Pendant VAD reduces unnecessary encoding/storage activity without losing
   speech.
2. App-side cheap VAD/noise gating decides whether assembled canonical audio is
   worth uploading; it does not turn each physical record into a conversation.
3. Remote VAD is a final server-cost/content gate. It does not merge local
   recordings and cannot repair broken ownership.

One-to-nine-second ring files may exist internally. They must be merged with
adjacent coverage before user display or upload. Noise-only assembled windows
may remain locally recoverable without creating a transcript or summary.

## Power policy

- Quiet operation should keep high-cost transfer and processing idle.
- Speech activates the current-conversation path and extends it through the
  conversation silence window.
- Historical sync is opt-in on battery and on charger.
- Charger presence may allow larger requested slices but never starve live
  capture.
- Battery claims require matched-duration, matched-audio, unplugged A/B runs;
  an observed percentage during development is not qualification.

## Non-negotiable failure rules

- Never send `ADVANCE` after a partial range, CRC failure, timeout, or failed
  durable registration.
- Never delete pendant data merely because one phone attempted a download.
- Never create a second conversation solely because transport reconnected.
- Never expose raw storage fragments as independent conversations.
- Never allow an automatic historical drain to compete with live capture.
- Never claim a firmware build ran without verifying the active image after
  reboot.
- Never treat updater success as application success without image identity,
  advertising, GATT readiness, live audio, and ring movement.
