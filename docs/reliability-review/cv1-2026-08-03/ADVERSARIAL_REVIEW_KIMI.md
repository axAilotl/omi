# Adversarial review — Omi CV1 storage-first branch (`codex/cv1-blackbox-diagnostics`)

Reviewer: independent (Kimi). Date: 2026-08-04. Host: x86_64 Linux, Docker 28.5.1,
pinned `ghcr.io/zephyrproject-rtos/ci:v0.26.13@sha256:b0ac6334d1926cd0971a0a444f7adc6dd020e88ee3ce865aa070b6475a3ac4eb`,
NCS v2.9.0 / Zephyr 3.7.99, BabbleSim (built in-container from the west
`+babblesim` group).

Scope reviewed: `source/` working tree at `ef4c9355b3` + uncommitted delta
(`patches/working-tree.patch`, SHA-256 verified against
`evidence/patch-sha256.txt`), committed delta
(`patches/committed-since-origin-main.patch`), and the pinned Zephyr
`adv.c`/`conn.c` in `evidence/pinned-zephyr/`. The implementation was not
modified; all experiments ran on copies under `/tmp`.

---

## Verdict

**Ready for physical qualification** — of the reconnect-fix candidate only —
**conditional on two pre-flash gates** (below). The packet's root cause, its
fix, and its regression test all survived direct falsification attempts,
including an independent end-to-end reproduction I ran on this host.

This verdict does **not** extend to release. I verified two high-severity
durability/authorization defects in the wider stack (V2, V3) that the packet
did not list, confirmed CV1-R05 at code level, and confirmed CV1-R01 is still
open in code. Those gate release, not the qualification runs.

**Pre-flash gates (must happen before any new OTA is built/flashed):**

1. **New build number.** The working tree still carries
   `CONFIG_MCUBOOT_IMGTOOL_SIGN_VERSION="3.0.30+106"`
   (`source/omi/firmware/omi/omi.conf:137`, byte-identical untracked
   `prj.conf:137`). Any OTA built from this tree would share a version string
   with the flashed build-106 artifact that contains the leak and the
   supervisor — the exact same-version-different-content contamination class
   as CV1-R01/R16. The brief acknowledges the missing build number; I am
   sharpening it to a hard gate.
2. **Harness artifact identity.** The internal DFU harness still flashes a
   fixed filename from Flutter Documents with no hash/manifest/signed-header
   verification and declares success without a post-reboot active-image check
   (V4). Running Phase 2 through it would again produce unattributable
   evidence. Complete Phase 1 first.

---

## 1. End-to-end reconstruction (verified against code)

```text
PDM mic -> Opus frames -> TX ring (ordered, backpressured) -> pusher thread
  -> storage-authoritative: SD ring record (seq, capture ts, CRC) FIRST
     (CONFIG_OMI_STORAGE_AUTHORITATIVE_CAPTURE=y, LIVE_PREVIEW=n in omi.conf:327-328)
  -> phone: one serial ring reader (RingStorageSync), READ_BEGIN -> DATA*
     -> DONE(status,next_seq,crc32) -> durable WAL (fsync + atomic manifest)
     -> only then CMD_RING_ADVANCE
  -> WAL compaction into conversation-bound canonical Opus file
  -> upload /v2/sync-local-files (transcript_mode=replace requested,
     NOT owned by backend — V3) -> conversation/timeline
```

The three-lane model (live head / recent-gap repair / explicit historical
backlog), one-serial-reader ownership, reconnect-preserves-conversation, and
fragment-hiding are implemented and, where tested, pinned by real tests (see
§5). `CONFIG_BT_MAX_CONN=1` confirmed in both `omi.conf:111` and
`bsim/prj.conf:4`.

---

## 2. The off-air incident: root cause verified, fix verified, mechanism verified at pinned-source level

**The leak is real and was introduced exactly where the packet says.**
`git show fb3718d100:omi/firmware/omi/src/lib/core/button_service.c` (PR
#10605, 2026-07-29) shows `button_notify()` acquiring
`get_current_connection()` — documented at `transport.h:58` as returning a
referenced `bt_conn` that "the caller must release" — and never calling
`bt_conn_unref()`. Production builds include the button FSM
(`CONFIG_OMI_ENABLE_BUTTON_INPUT` defaults `y` under `OMI_ENABLE_BUTTON=y`;
`button.c` compiled per `CMakeLists.txt:47-49`), so every physical button
event while connected leaked one reference. The likely origin is visible in
`source/omi/firmware/devkit/`: the devkit's `get_current_connection()`
returns a **borrowed, unreferenced** pointer (`devkit/src/transport.c:873-876`)
and its callers correctly never unref; the CV1 copy kept the devkit call
pattern against a ref-counted contract.

**The fix is present and correct.**
`source/omi/firmware/omi/src/lib/core/button_service.c:66-70` — notify, then
`bt_conn_unref(conn)` on the only non-NULL path. No double-unref is possible
(the reference is private to the call), and `bt_gatt_notify` copies its
parameters synchronously, so unref-after-notify is safe.

**The Zephyr lifecycle explanation is confirmed line-by-line in the pinned
sources:**

- Connectable legacy advertising pre-reserves a connection object:
  `bt_le_adv_start_legacy` → `le_adv_start_add_conn` → `bt_conn_add_le` →
  `acl_conn_new()` (fails when no ref==0 slot) → `-ENOMEM`
  (`evidence/pinned-zephyr/adv.c:916-933, 1064-1075`).
- For persistent undirected advertising, `-ENOMEM` jumps to `set_adv_state`
  and **returns 0 without enabling the controller**
  (`adv.c:1068-1071, 1097-1115`) — exactly the "returns success but stays
  off-air" behavior the brief describes.
- Resume happens only from the final `bt_conn_unref` on a deallocated
  peripheral connection (`evidence/pinned-zephyr/conn.c:1548-1556` →
  `bt_le_adv_resume`, `adv.c:1476-1540`) or the advertising-timeout event
  (`adv.c:2252-2256`). A leaked reference keeps `ref > 0`, the slot is never
  recycled, `bt_le_adv_resume` either never fires or fails in
  `le_adv_start_add_conn`, and the pendant stays off-air until reboot. A cold
  reboot clears it. This matches the physical incident signature precisely.

**All other CV1 connection-reference paths are balanced.** I audited every
`get_current_connection()` / `bt_conn_ref/unref` site in the CV1 tree:
`transport.c` (charging-CCC 367/370, battery 631/666, bulk-link 931/941,
link-setup 1041/1044/1071, test_pusher 1513/1530, pusher 1571/1668,
`transport_off` 1824-1828, `set/take_current_connection` 2026-2045),
`storage.c` storage-thread loop (743/879), `button_service.c` (fixed). The
mutex-protected `current_connection` handoff cannot hit the `bt_conn_ref`
from-zero assert. No second leak, no double-unref, no stale-session conn use
found in CV1 production code.

**Empirical A/B proof (run by me on this host, pinned container):**

| Variant | Result |
|---|---|
| Working tree verbatim (fix present) | `OMI_BSIM_PASS` at sim 5.182120 s; second connection at 2.730632 s, **109 ms after** the 2.621814 s disconnect |
| Same tree with only the unref reverted (byte-level match to old production `button_notify`, verified by diff against `git show HEAD:`) | connect → button event → disconnect at 2.621814 s → **no re-advertising, no second connection, no PASS**; runner exit 1 |

Simulated timestamps reproduce the packet's claimed numbers to the
microsecond. Commands and full output in §8.

**Residual honesty note:** the *physical* incident's attribution to this leak
remains inference — no conn-pool telemetry was captured from the pendant. But
the leak is a verified defect with certainty, the pinned stack turns it into
exactly the observed symptom with certainty (proven in simulation), and no
competing explanation survived audit (§5). A network-core crash could produce
the same external signature and cannot be excluded from the physical evidence;
that is what the 25-cycle physical matrix is for.

---

## 3. Supervisor removal: correct, with one accepted gap

- For the post-disconnect case, Zephyr's persistent-advertising lifecycle
  resumes advertising by itself from the final unref (`conn.c:1553-1556`). No
  application supervisor is needed once references are balanced.
- The removed supervisor could never repair the leak: its
  `bt_le_adv_start` would take the same `-ENOMEM` → `set_adv_state` →
  return-0-without-enabling path (`adv.c:1066-1074`), so it churned the radio
  while achieving nothing. Removal is justified; a bounded watchdog is **not**
  justified, because no independent controller defect has been proven.
- **Gap (accepted, but now uninstrumented):** if the *initial* boot-time
  `bt_le_adv_start` fails for any reason other than conn-pool exhaustion,
  `transport.c:1977-1983` logs and continues — the pendant stays off-air
  until reboot, and unlike builds 104/106 there is now no recovery and no
  blackbox counter/event on that failure. The only observed cause of the
  physical failures is explained by the leak, but the boot path's
  distinguishability regressed. Minimal recommendation: record a blackbox
  event on initial-adv-start failure (no retry loop) so a future physical
  occurrence is attributable. See R1.
- No supervisor remnants remain in code (only three adv call sites exist:
  `transport.c:1831,1977` and dead-for-CV1 `lib/evt/ble.c:137`), but the
  diagnostics enums `BLACKBOX_COUNTER/EVENT_BLE_ADVERTISING_RECOVERY`
  (`blackbox.h:886-899`), their Dart parser entries
  (`blackbox_protocol.dart`), and the docs
  (`CV1_BLACKBOX_DEVICE_TESTING.md:99-101,221-229`,
  `STORAGE_FIRST_DEMO.md:38-41`) still describe the removed supervisor as
  present. Doc/enum drift — low severity, but it will misread the next
  export.

---

## 4. Verified defects

### V1 — (root cause, fixed in tree) `button_notify` connection-reference leak
- Severity: **critical** (historical; fix verified).
- `source/omi/firmware/omi/src/lib/core/button_service.c:63-70`; introduced by
  `fb3718d100` (PR #10605).
- Contract: `transport.h:58` ownership contract; product rule "pendant must
  become observable without touch after client disconnect".
- Failure sequence: any button event while connected → +1 conn ref → on
  disconnect the only (`MAX_CONN=1`) conn object never recycles → persistent
  legacy advertising cannot resume (`adv.c:1497-1500`) → pendant off-air until
  cold reboot.
- Tests: caught now by the two-connection BabbleSim test (verified it fails on
  the old code — §2). Not caught by any host unit test.
- Fix: present. Regression test: present and behaviorally discriminating.
- Confidence: certain. Evidence: source diff + pinned Zephyr source +
  simulator A/B reproduction.

### V2 — App: canonical conversation file is never fsynced before its physical sources are deleted
- Severity: **high** (narrow trigger: OS crash/power loss in a seconds-wide
  window; consequence: unrecoverable audio loss after pendant ADVANCE).
- `source/app/lib/services/wals/conversation_audio_assembler.dart:141-186`:
  canonical artifact written via `partial.openWrite()` (`IOSink`),
  `await sink.flush(); await sink.close();` then `partial.rename(...)`.
  `IOSink.flush()/close()` do **not** fsync (only `RandomAccessFile.flush()`
  does — dart-lang/sdk#8794). Then `local_wal_sync.dart:2160` commits the
  fsynced manifest (canonical becomes the only referenced copy) and
  `:2192-2202` deletes every compacted source.
- Contract violated: "Compaction paths that retire physical members [only]
  before canonical file fsync" (BUG_REGISTER data-loss hotspot);
  ARCHITECTURE: "Physical WAL boundaries remain internal" durability chain.
- Failure sequence: assemble → rename → manifest fsynced → sources deleted →
  phone OS crash before writeback → canonical file zero-length/missing → next
  `_prepareHistoricalRingFragments` marks it `corrupted` (terminal) → pendant
  copy long since ADVANCED. Contrast: the per-range WAL write
  (`ring_storage_sync.dart:1620`) and the manifest both correctly use
  `flush: true`; only the assembler skips it.
- Current tests: **not caught** — assembler tests cover tiling/malformed
  input, not durability ordering.
- Minimal fix: write via `RandomAccessFile` and `flush()` (fsync) before
  rename, or open the renamed file and fsync it + fsync the directory before
  manifest commit. Regression test: inject a crash between rename and
  source-deletion (or assert the fsync seam is invoked before
  `_saveWalsToFile()` in the compaction flow).
- Confidence: high. Evidence: source (the fsync semantics rest on documented
  Dart SDK behavior — flagged as the one non-statically-verifiable link).

### V3 — Confirmed CV1-R05 at code level: `transcript_mode=replace` is silently dropped by the backend
- Severity: **high** (final transcript/timeline correctness).
- App: `source/app/lib/backend/http/api/conversations.dart:577-579` appends
  `transcript_mode=replace` for canonical replacements
  (`local_wal_sync.dart:2703`). Backend:
  `source/backend/routers/sync.py:859-873` declares no such query parameter;
  a full-backend grep for `transcript_mode|replace_transcript` is empty.
  FastAPI silently ignores unknown query parameters, so the app marks the
  canonical WAL `synced`/`uploaded` as if replacement were owned.
- Amplifier verified in app code: a rejected live delivery is never replayed
  (`ring_storage_sync.dart:829-832` skips durable `miss` WALs) — the design
  relies on canonical recovery + replace to repair the open conversation, so
  an ignored replace leaves recovered audio appended beside the live-origin
  text. Matches the registered production symptom.
- Contract violated: backend canonical-ownership invariant; packet's own
  "do not claim end-to-end transcript correctness".
- Current tests: not caught (no end-to-end marker test exists).
- Minimal fix: backend declares and atomically owns
  replace-with-source-coverage; until deployed, the release must explicitly
  exclude automatic canonical replacement (as the packet's gates already say).
- Confidence: certain at the contract level (parameter undeclared). Evidence:
  source, both sides.

### V4 — DFU harness: no artifact identity verification; new gate can pass while the native service still owns the pendant (CV1-R01 confirmed open in code)
- Severity: **medium** (diagnostic-only harness, but it is the qualification
  instrument — its failure mode is evidence contamination, see CV1-R16).
- `source/app/lib/pages/settings/blackbox_dfu_harness.dart:14,79-82`: fixed
  filename from `getApplicationDocumentsDirectory()`, flashed unconditionally.
  `firmware_mixin.dart:191-197` checks only `file.exists()`;
  `processZipFile` parses `manifest.json` but compares nothing.
  `firmware_mixin.dart:223-225` maps updater `success` → "Firmware installed"
  with no post-reboot MCUmgr image-list check. No hash/manifest/signed-header
  verification was added by the working tree — the patch adds only
  documentation.
- New race: the gate changed to `ensureConnection(device.id) != null`
  (`blackbox_dfu_harness.dart:66-69`, polling at 500 ms) while the DFU suspend
  is keyed on `provider.connectedDevice`
  (`device_provider.dart:1077-1080`), which is set via a debounced handler. A
  native PASSIVE auto-reconnect can satisfy the harness gate before the
  provider processes the connection → `prepareDFU()` no-ops → MCUmgr attaches
  while `OmiBleForegroundService` still manages the device; because
  `unmanageDevice` never ran, `BleCompanionService.handleDeviceAppeared` can
  even fire `forceReconnect` mid-transfer.
- Contract violated: "Never claim a firmware build ran without verifying the
  active image after reboot"; single-owner DFU suspension.
- Current tests: `blackbox_dfu_harness_test.dart` pins only the `canStart`
  truth table. Not caught.
- Minimal fix: Phase 1 as written in the packet (hash + manifest + signed
  header + pre/post image list as code, plus the two-same-name-ZIP regression
  test), and gate `startMCUDfu` on a completed suspend acknowledgement, not on
  GATT presence.
- Confidence: certain that no verification exists; the race window is
  statically constructed, not observed. Evidence: source.

### V5 — Firmware: storage command channel is unauthenticated; CLEAR/ADVANCE are trusted and CLEAR is uncounted
- Severity: **high** as a design property (threat-model dependent: with
  `MAX_CONN=1` a rogue central must win the connection race), **not a
  regression** of this branch.
- `source/omi/firmware/omi/src/lib/core/storage.c:84-89`: storage write
  characteristic is `BT_GATT_PERM_WRITE` — no `_ENCRYPT`/`_AUTHEN`; no
  `bt_conn_set_security` anywhere in `src/`; `CONFIG_BT_SMP=y` is configured
  but never enforced. `storage.c:681-698` accepts `CMD_RING_ADVANCE` /
  `CMD_RING_CLEAR` from any connected central. `sd_card.c:1173-1196` honors
  ADVANCE for any value in `[read_seq, write_seq]` — unbound to any completed
  transfer. `sd_card.c:1077-1099` (`clear_ring_internal`) zeroes
  read/write/**dropped** — a rogue CLEAR destroys all unsynced audio
  *and* erases the evidence (never counted as dropped).
- Contract violated: "Never delete pendant data merely because one phone
  attempted a download" — here zero downloads are needed.
- Current tests: not caught (no GATT-permission or authorization test).
- Minimal fix: require an encrypted/bonded link for the storage command
  characteristic; count CLEAR-retired records in `dropped_packets`; consider
  binding ADVANCE to a completed DONE in the same connection session.
  Regression test: unpaired central issues CLEAR/ADVANCE → rejected; CLEAR
  accounting test in the host packer suite.
- Confidence: certain (static). Evidence: source.

### V6 — Latent: `sd_ring_read` 15 s timeout leaves a dangling stack `out_buf`
- Severity: **medium, latent** — live memory corruption only if the dead
  legacy file-list API regains a caller.
- `sd_card.c:1664-1670` (`get_packet_name_for_seq`) passes a stack
  `uint8_t packet[RAW_AUDIO_PACKET_BYTES]` as `req.u.read.out_buf`. On the
  15 s worker-response timeout (`sd_card.c:2332-2335`) the caller returns, but
  the queued request still holds the pointer; the worker later `memcpy`s up to
  444 bytes into a dead stack frame (`read_packets_internal`,
  `sd_card.c:1162`). The `read_in_flight` CAS protects `resp`, not `out_buf`.
  The only caller (`get_audio_file_list_with_sizes`, `sd_card.c:2527`) has no
  in-tree caller today — hence latent.
- Current tests: not caught (sd_card.c has zero host coverage).
- Minimal fix: static buffer for that path, or cancel/drain the queued request
  on timeout, or delete the dead API.
- Confidence: certain as code inspection; trigger unreachable today. Evidence:
  source.

### V7 — A second READ while a transfer is active silently abandons the in-flight transfer
- Severity: **low-medium** (requires phone misbehavior; ring cursor is safe —
  the risk is phone-side assembly confusion from interleaved streams).
- `storage.c:817-850` processes `read_request_pending` unconditionally;
  `start_pending_read` (`storage.c:475-508`) overwrites
  `transfer_start_seq/current_read_seq/remaining_packets/transfer_data_crc`
  with no `transfer_active` guard and emits no `DONE(status!=0)` for the
  superseded transfer. Firmware has no `-EBUSY` rejection.
- Current tests: not caught (no host harness for the storage command state
  machine).
- Minimal fix: reject or queue a READ while `transfer_active`; on
  supersession, terminate the old transfer with an explicit error DONE.
- Confidence: certain (static). Evidence: source.

### V8 — Unsubscribe-mid-transfer busy-spins the storage thread at 1 ms
- Severity: **low** (power/liveness; no data-integrity impact — other commands
  still process).
- `storage_notify` returns `-EAGAIN` when CCC is off (`storage.c:247-249`);
  `ring_control_response_should_retain(true, -EAGAIN)` is true, so both the
  READ_BEGIN retry (`storage.c:526-530`) and the DONE retry
  (`storage.c:856-859`) loop `k_msleep(1)` indefinitely until disconnect or
  STOP. A phone that unsubscribes without disconnecting wedges the transfer at
  preemptive priority 7.
- Minimal fix: treat unsubscribed as terminal for the transfer (fail the
  transfer with DONE status or stop it), not as retainable backpressure.
- Confidence: certain (static). Evidence: source.

### V9 — iOS reconnect loop is unbounded at a fixed 200 ms, no backoff
- Severity: **low-medium** (battery/radio churn when the pendant repeatedly
  accepts-then-drops: owned by another host, marginal RF).
- `source/app/ios/Runner/Ble/OmiBleManager.swift:822-828` (didDisconnect) and
  `:784-789` (didFailToConnect): `asyncAfter(200ms) { connect(...) }`
  unconditionally. Android's equivalent is exponential backoff capped at 30 s
  with a parked passive auto-connect
  (`BleReconnectBackoff.kt:16-23`, `OmiBleForegroundService.kt:546-561`).
- Contract: no battery-amplifying loops; platform parity (CV1-R15).
- Minimal fix: port the bounded-backoff-then-park policy; pin with a test.
- Confidence: certain the loop is unbounded; battery magnitude unmeasured.
  Evidence: source.

### V10 — Storage-tail restart loop is unbounded (rate-capped, never terminal) and null-start paths escape recovery
- Severity: **low** (bounded 16 s cadence → churn, not hammer; but no terminal
  user-visible "recovering" state, and two silent no-retry holes).
- `capture_controller.dart:1150-1200`: exponential delay capped at 16 s, reset
  only when live frames flow, no max attempts, no surfaced terminal state —
  while the socket stays `serverReady`, a pendant stuck in SD-not-ready is
  retried forever (each cycle = ensureConnection + codec + device-info + up to
  6 RING_INFO round trips). Also, the new `startStorageTailRecoverably`
  wrapper converts only *thrown* errors; `startAudioTail` returning `null`
  (generation race / `connection == null`, `ring_storage_sync.dart:460-488`)
  and the `connection == null` early return
  (`capture_controller.dart:1318`) schedule no retry when entered from
  `_resetStateOnce`/socket-reconnect — capture can sit tail-less until the
  next external event.
- Contract: UI truthfulness during recovery (must say "recovering"); battery
  policy.
- Minimal fix: max-attempt or total-time bound → surface a truthful degraded
  state; treat null-start as a restart signal. Tests for both.
- Confidence: certain (static); battery magnitude unmeasured. Evidence:
  source.

---

## 5. Invalidated concerns (checked; the packet's position holds)

- **ADVANCE-before-durability (app side):** correctly gated — durable WAL
  registration (fsync + atomic manifest) completes inside
  `flushValidatedRange` before `canAdvance` is evaluated; flush error, CRC
  mismatch, cancel, incomplete range, and protocol error each independently
  block ADVANCE (`ring_storage_sync.dart:1523-1579`). Pinned by
  `ring_storage_sync_test.dart:1283,1298,1339`. Firmware-side, `k_msgq_put`
  timeout maps to DONE status 9 with CRC over exactly the emitted prefix — no
  silent truncation.
- **DONE retry duplication/skip:** impossible — DONE carries no records; the
  retained retry resends the identical 14-byte response
  (`storage.c:856-859`, `ring_transfer_integrity.c:139-149`).
- **Immutable bounded read (CV1-R04 closure):** the snapshot is latched by the
  `REQ_GET_RING_INFO` inside `start_pending_read`
  (`commit_pending_writes_for_snapshot`, `sd_card.c:1827-1841`) before
  `remaining_packets` is frozen and READ_BEGIN sent; chunks read only the
  frozen window; producer growth cannot extend it; wrap past the cursor fails
  loudly with `-ERANGE`. **All three** `sd_ring_read` callers pass
  `snapshot_latched=true` (`storage.c:567`, `sd_card.c:1667,2585`) — the old
  re-drain path is unreachable in production (see T3).
- **Frame ordering under SD pressure:** retained at every stage —
  `broadcast_audio_packets` applies sleeping backpressure rather than dropping
  (`transport.c:2092-2097`); the pusher keeps the popped frame
  (`retained_tx_frame`, `transport.c:1563-1564,1610-1611,1672-1685`); the
  packer keeps rejected records. Chronology cannot invert; `dropped_packets`
  counts only previously-durable records made unreachable (wrap
  `sd_card.c:996-1008`, recovery reconcile, torn tail) — matches the contract.
- **Reconnect ≠ new conversation; preview survives:** reclaim/reconcile pinned
  (`device_provider_test.dart:329`); raw 1-9 s fragments are hidden from UI
  and excluded from upload (`sync_provider.dart:134-138`,
  `local_wal_sync.dart:483,908-917`); ten physical archives = one logical row
  (`sync_provider_sync_wal_wake_test.dart:536`).
- **Historical-lane authority:** deep backlog requires Auto Sync or an
  explicit Sync; charging is never consulted; live preempts history (one
  recovery slice per poll after the live read, `ring_storage_sync.dart:947-950`).
- **Android session binding:** session-id-keyed completions, exact-identity
  take, `retireGattSession`, `isActiveGatt` gates, memoized DFU
  release→resume, bounded backoff (500 ms→30 s, jitter), retry path kept
  PASSIVE after the `BleGattConnectionMode` change. No stale-session
  completion path found.
- **iOS unapproved-restored-pendant release:** verified
  (`OmiBleManager.swift:685-724`); only a real foreground transition consumes
  the gate.
- **RTC-loss replay:** invalid time emits timestamp **0**, never a stale value
  (`ring_transfer_integrity.c:27-30`).
- **Force-stop masking firmware failure:** impossible in the relevant
  direction — Android cannot suppress pendant-side advertising; the 60 s+
  no-advertisement observation after force-stop is pendant behavior.
- **Emergency reboot vs durability commit:** the 30 s reboot fires only from
  the button path, which reaches it either after all durability gates passed
  (fence is after commit) or after a cancelled shutdown with capture resumed —
  in which case SD writes may be in flight, but the ring's barrier-ordered
  commit + recovery reconcile is explicitly designed for power loss. Low.

---

## 6. Plausible risks requiring discriminating tests

- **R1 — Boot-time advertising failure is now unrecoverable and
  uninstrumented** (`transport.c:1977-1983`). Supervisor removal is correct
  for the disconnect case, but any non-conn-pool initial-start failure
  (sick network core, HCI race) leaves the pendant off-air until reboot with
  no counter. Test: fault-inject initial `bt_le_adv_start` failure on target
  (JTAG) or in bsim; decide from evidence whether a *one-shot bounded* retry
  is justified. Add a blackbox event either way.
- **R2 — A zero-decodable-frame record can wedge the live lane forever**
  (`ring_storage_sync.dart:1431-1436`: `protocolError=true` but counted
  consumed → `receivedCompleteRange` passes while `canAdvance` fails → tail
  dies → R1's loop re-reads the same CRC-valid corrupt range forever → ring
  eventually wraps, `dropped` grows). Precondition (such a record durably
  stored) is unverified — needs firmware-side evidence or a skip-and-quarantine
  policy.
- **R3 — Stale in-memory coverage can authorize ADVANCE over a locally
  deleted, never-uploaded range** (`ring_storage_sync.dart:473` coverage
  loaded once; `local_wal_sync.dart:2253-2260` deletes disk files without
  invalidating the running tail's coverage; next covered-prefix advance
  discards the pendant copy). Trigger is explicit user deletion of a pending
  recording — arguably authorized, but the user was told they deleted a phone
  copy, not the only copy. Test: delete a `miss` WAL mid-tail; assert no
  covered-prefix ADVANCE spans it.
- **R4 — No app-side writeSeq liveness watchdog** — the 1 Hz `getRingInfo`
  poll never compares successive `writeSeq`; build-102's PDM false-ready
  (Connected/Listening with a frozen cursor) is still undetectable in Dart
  (CV1-R03 mitigation is firmware-side only). Needs VAD-aware discrimination
  (a naive counter false-positives during legitimate silence).
- **R5 — Non-atomic command state shared between the BT RX thread and the
  storage thread** (`pending_start_seq` u64, `*_requested` flags in
  `storage.c`) — program-order safe on the single-core M33 today, strictly
  C UB; breaks under any future SMP/reordering change.
- **R6 — `k_sem_init` on `audio_tx_sem` with possible live waiters at
  disconnect** (`transport.c:815-817`; storage thread may be inside
  `transport_bulk_tx_acquire`, pusher inside `k_sem_take`). Both waits are
  timeout-bounded; Zephyr does not document re-init with waiters. Soak test:
  disconnect-during-bulk-sync.
- **R7 — System-workqueue blockage during graceful shutdown.** `turnoff_all`
  runs entirely on the system workqueue (`button.c` `button_work`) and can
  block it for haptic(0.3 s) + `codec_drain`(≤15 s) +
  `transport_prepare_shutdown`(≤45 s) + SD/transport teardown + the release
  fence (until physical release). Delayed works (link setup, storage snapshot
  retry, battery) stall meanwhile. Mostly benign by design (shutdown is
  intentional; adv resume does not use the system workqueue), but the "30
  second emergency hold" can in the worst case take 60+ s to reboot — the
  public docs overstate its immediacy.
- **R8 — Android DIRECT/PASSIVE remapping is unpinned.** `bluetoothOn`,
  re-manage, and `forceReconnect` changed from `autoConnect=true` to DIRECT
  (`OmiBleForegroundService.kt:375,446,477`); recovery now depends on the
  failed DIRECT attempt reliably producing a DISCONNECTED callback so the
  backoff path arms a PASSIVE retry. `BleGattConnectionModeTest.kt` pins only
  the enum, not the call-site mapping; a one-line edit would silently flip the
  battery-critical retry at `:557`. Discriminating test: BT toggle while the
  pendant is mid advertising gap → assert eventual reconnect.
- **R9 — iOS has no session/generation binding for GATT completions**
  (string-keyed completions, `OmiBleManager.swift:267-296`); stale-callback
  safety rests on disconnect-time failing of pending completions and
  CoreBluetooth serialization. No stale path constructed statically; unlike
  Android, nothing pins it.
- **R10 — Physical attribution caveat** (carried from §2): leak sufficiency is
  proven; necessity on the physical pendant is inference. A network-core fault
  is not excluded by the physical evidence. The 25-cycle matrix with
  independent scans discriminates.

---

## 7. Test and environment defects

- **T1 — The bsim failure mode on old code is a hang, not an assertion.** The
  client's second `connect_once()` blocks on `k_sem_take(K_FOREVER)`
  (`bsim/client/src/main.c:215`); the runner detects failure only via its
  120 s poll / `sim_length=30e6` end (`scripts/ci/run-bsim.sh:57-70`). It is
  CI-discovered (exit 1) but a timeout signature is weaker than an explicit
  one, and it cannot distinguish "never re-advertised" from "slow". Minimal
  improvement: bound the second connect (`K_SECONDS(15)`) and print
  `OMI_BSIM_FAIL reconnect_timeout`.
- **T2 — The test is otherwise behavioral, deterministic, and discriminating**:
  it executes the production `button_notify` path on the production transport
  with production `MAX_CONN=1`, requires a real second connection (advertising
  observability proven end-to-end), and I verified it passes on the fixed tree
  and fails on the old tree. It does not, however, exercise multiple button
  events across multiple disconnects (the leak is per-event); a loop of N
  connect/button/disconnect cycles would harden it against partial fixes.
- **T3 — `snapshot_latched` is dead weight.** Every production caller passes
  `true`; the `false` branch (the CV1-R04 starvation path) is unreachable, and
  the regression test pins only the pure predicate
  (`test_latched_ring_transfer_does_not_recommit_live_producer_queue`), giving
  a false impression of guarded production behavior. Either remove the
  parameter or assert at the `REQ_READ_PACKETS` level.
- **T4 — Host suite reproduced on this host (x86_64 Linux, cmake 3.28.3,
  gcc):** `audio_storage_packer_tests` and `blackbox_trace_tests` 2/2 PASS
  (§8). Suite is policy-level only, as the packet itself states.
- **T5 — Not executed here:** the Flutter/Dart, Kotlin, and Swift suites (no
  Flutter/Dart SDK on this host) and `make preflight`/`pr-preflight`. The
  app-side findings above are from static audit of the exact sources; the
  named Dart tests were read but not run. This is the review's main
  environmental limitation.
- **T6 — Config duplication is currently in sync but fragile:** untracked
  `omi/firmware/omi/prj.conf` is a byte-identical copy of `omi.conf` (diff
  verified), produced by `build-cv1.sh` (`cp omi.conf prj.conf`). Building
  outside that script against a stale `prj.conf` silently builds different
  firmware. Acceptable if the CI script is the only build path; worth a
  preflight assert.

---

## 8. Commands and outputs (reproduction log)

Patch integrity:

```text
$ sha256sum -c evidence/patch-sha256.txt
patches/committed-since-origin-main.patch: OK
patches/working-tree.patch: OK
```

Host suite (this machine):

```text
$ cmake -S source/omi/firmware/omi/tests/audio_storage_packer -B $b && cmake --build $b && ctest --test-dir $b --output-on-failure
1/2 Test #1: audio_storage_packer_tests .......   Passed
2/2 Test #2: blackbox_trace_tests .............   Passed
100% tests passed, 0 tests failed out of 2
```

BabbleSim A/B (pinned container; `FW=<copy>` so `source/` was never touched;
orchestration script `/tmp/kimi-bsim/run-experiment.sh`; full logs
`/tmp/kimi-bsim/{fixed-run,leaky-run,experiment}.log`):

```text
Variant A (working tree verbatim):
  docker run --rm -v /tmp/kimi-bsim/fixed/firmware:/omi/firmware \
    -e CMAKE_PREFIX_PATH=/opt/toolchains $PINNED_IMAGE \
    bash /omi/firmware/scripts/ci/run-bsim.sh
  exit 0
  d_00: @00:00:00.120484 (CPU:0): OMI_BSIM_BUTTON_NOTIFIED
  d_00: @00:00:02.621814 (CPU:0): transport: Transport disconnected
  d_00: @00:00:02.730632 (CPU:0): transport: Transport connected
  d_01: @00:00:05.182120 OMI_BSIM_PASS

Variant B (only the bt_conn_unref reverted; verified byte-identical to
`git show HEAD:.../button_service.c` modulo the (void) cast):
  exit 1
  d_00: @00:00:00.120484 (CPU:0): OMI_BSIM_BUTTON_NOTIFIED
  d_00: @00:00:02.621814 (CPU:0): transport: Transport disconnected
  (no second "Transport connected"; no OMI_BSIM_PASS; runner timeout)
```

Origin verification:

```text
$ git show fb3718d100:omi/firmware/omi/src/lib/core/button_service.c | sed -n '63,70p'
void button_notify(uint8_t event) {
    final_button_state[0] = event;
    struct bt_conn *conn = get_current_connection();
    if (conn != NULL) {
        bt_gatt_notify(conn, ...);      /* no bt_conn_unref — old production */
```

---

## 9. Release / physical-qualification gates (reviewer-adjusted)

Before flashing the candidate (additions to the packet's Phase 1/2):

1. Bump `CONFIG_MCUBOOT_IMGTOOL_SIGN_VERSION` (and DIS rev if policy requires)
   **before** building; record ZIP/manifest/header/image hashes (gate G1).
2. Implement harness identity verification in code (hash, manifest version,
   signed header, pre/post MCUmgr image list) and gate DFU start on a
   completed suspend acknowledgement (V4). Do not run Phase 2 through the
   current harness.
3. Then the packet's Phase 2 as written: postboot active/confirmed listing,
   25× [connected button event → force-stop/BT-toggle → independent scan →
   exact-device reconnect → moving RingInfo → unique marker], plus one run
   with **multiple** button events across the connection to cover the
   per-event leak class (T2).
4. Optional but cheap: blackbox event on initial adv-start failure (R1) before
   the matrix, so any residual off-air occurrence is attributable.

Before any release (beyond the packet's existing gates):

5. Fix V2 (canonical fsync before source retirement) with a crash-window
   regression test.
6. Decide and enforce storage-command authorization (V5); at minimum count
   CLEAR-retired records as dropped and require link encryption.
7. Resolve V3: backend owns `transcript_mode=replace` atomically, or the
   release explicitly excludes automatic canonical replacement.
8. Fix or accept-with-tests: V7 (second-READ rejection), V8 (unsubscribe
   spin), V9 (iOS backoff), V10 (bounded tail restart + truthful recovering
   state), V6 (dead-API cleanup).
9. Refresh the stale docs/enums describing the removed supervisor (§3) and the
   emergency-reboot timing claim (R7).

*Report ends. No implementation files were modified; no production services
were accessed; no hardware was flashed.*
