# MeetingAssistant Rebuild (Phase 1 spike)

This is the hybrid rebuild of MeetingAssistant described in `../REBUILD_PLAN.md`: a
React/TypeScript UI inside a Tauri shell, talking to a small headless Swift sidecar that does
the native work. It is a separate app from the native SwiftUI app in the repo root, which is
left completely untouched.

Phase status: Phase 1 (spike) and Phase 2 (frozen contracts + seam checks) are complete and
reviewed; see `PHASE1_REPORT.md` and `CONTRACT.md`. Phase 3 implements the full headless
command surface in the sidecar: the real recording lifecycle (pause/resume/mute,
`recording.json`, on-device transcription via the core's `MeetingRecorder`), model
management, library, export, and storage/retention. The root package stays untouched; the
sidecar reuses the core services and the unused SwiftUI views are simply never instantiated.
The React UI is still the Phase 1 spike panel and gets rebuilt as vertical slices in Phase 4.

Phase 3 behaviour notes: recordings now land in the real recordings root (default
`~/Documents/MeetingAssistant Recordings`, shared with the native app), `record.start`
requires the Whisper model on disk, and `record.stop` transcribes before responding. The
sidecar keeps its own UserDefaults domain; see `CONTRACT.md` section 6.

## Architecture

```
Tauri shell (Rust)  --spawn + NDJSON over stdio-->  meetingcore-sidecar (Swift)
   |                                                    |
React/TS UI (WKWebView)                          reuses MeetingAssistantCore:
                                                 PermissionCenter, SystemAudioCaptureService
```

- `sidecar/` is a Swift executable that depends on the root package via a read-only path
  dependency and drives the existing `PermissionCenter` and `SystemAudioCaptureService`. It
  writes `system.caf` and `microphone.caf` and reports levels and status.
- `app/src-tauri/` is the Rust glue: it spawns the sidecar, forwards every sidecar stdout line
  to the webview as a `sidecar-event`, and sends command lines to the sidecar's stdin.
- `app/src/` is the minimal React UI.

## Identities

| Role | Bundle id |
| --- | --- |
| Rebuild app | `com.devswift.MeetingAssistant.rebuild` |
| Rebuild sidecar | `com.devswift.MeetingAssistant.rebuild.sidecar` |
| Native dev (do not reuse) | `devswift.MeetingAssistant` |
| Native release (do not reuse) | `com.devswift.MeetingAssistant` |

Both rebuild identities are ad-hoc signed with a pinned identifier and designated requirement,
mirroring `../script/package_release.sh`, so their TCC permissions stay stable and never
collide with the native app.

## Prerequisites (on your Mac)

- macOS 15 (Sequoia) or later.
- A Swift 6.2 toolchain (Xcode 16 or later).
- A Rust toolchain (`rustup`, stable). Install from https://rustup.rs if needed.
- Node 18 or later (`node`, `npm`).

## Build and run

```bash
./rebuild/scripts/build_and_run.sh
```

This builds the sidecar (`swift build -c release`), the frontend (`npm install && npm run
build`), and the Tauri shell (`cargo build --release --features custom-protocol`, which embeds the
built frontend into the binary; without it the app would look for a Vite dev server and render
a blank window); stages them into
`rebuild/dist/MeetingAssistant Rebuild.app`; embeds the sidecar at `Contents/MacOS/`; co-signs
the sidecar first and the app second with pinned identifiers and designated requirements; prints
the `codesign` verification for both; and launches the app. Use `build` as the first argument to
stop before launching.

The first build downloads Rust crates and the Swift package graph (including WhisperKit, which
the core depends on even though Phase 1 never calls it), so it takes a while. Later builds are
fast.

## The macOS permissions flow

Test permissions only from the signed bundle above. TCC keys off the signed identity, so
`tauri dev` will show different (or missing) permission state.

1. Launch the app and click **Request permissions**.
2. The Microphone prompt appears first; allow it.
3. Screen Recording cannot be granted by prompt alone. Enable **MeetingAssistant Rebuild**
   under System Settings, Privacy and Security, Screen Recording, then quit and reopen the app.
   macOS only applies Screen Recording after a relaunch. This matches the native app's
   `screenRecordingNotReady` behaviour.
4. Reopen, confirm both pills read `authorized`, then click **Record 3 seconds**.
5. The capture panel shows the output folder and the two `.caf` paths with non-zero byte sizes.

## Dev mode (fast UI iteration only, no real permissions)

```bash
cd rebuild/sidecar && swift build -c release
cd ../app && MEETINGCORE_SIDECAR="$(cd ../sidecar && swift build -c release --show-bin-path)/meetingcore-sidecar" npm run tauri dev
```

`MEETINGCORE_SIDECAR` points the shell at the freshly built sidecar binary. This is for UI work
only; the dev process is not signed with the pinned identity, so do not draw permission
conclusions from it.

## Frozen contracts and seam checks (Phase 2)

The authoritative contract document is [`CONTRACT.md`](./CONTRACT.md): the full sidecar
protocol (implemented and reserved commands, events, error codes) and the frozen on-disk
`recording.json` format. The TypeScript mirror is `app/src/contract.ts`; the Swift reference
shapes stay untouched in the root package.

Seam regression checks live in `sidecar/Tests/SeamTests/` and spawn the real sidecar binary
over NDJSON. Run them with:

```bash
./rebuild/scripts/seam_check.sh
```

The capture check records about two seconds of real audio and needs Microphone and Screen
Recording granted to your terminal app; without them it skips with a message. The suite also
roundtrips a golden `recording.json` fixture through the core's own Codable types to catch
format drift.

## Frozen sidecar contract

NDJSON over the sidecar's stdin/stdout. stderr is human-readable logging only.

```
Command:   { "id": "c1", "cmd": "name", ...params }
Response:  { "id": "c1", "ok": true, "result": {...} }
           { "id": "c1", "ok": false, "error": { "code": "...", "message": "..." } }
Event:     { "event": "name", ...fields }
```

Phase 1 commands:

```
{ "id": "c1", "cmd": "permissions.status" }
{ "id": "c2", "cmd": "permissions.request", "kinds": ["microphone", "screen"] }
{ "id": "c3", "cmd": "record.start", "outputDir": "...optional in Phase 1...", "micDeviceId": "...optional..." }
{ "id": "c4", "cmd": "record.stop" }
```

Phase 1 events:

```
{ "event": "ready", "protocol": 1, "sidecar": "0.1.0", "pid": 1234, "bundleId": "com.devswift.MeetingAssistant.rebuild.sidecar" }
{ "event": "status", "value": "recording|completed|failed" }
{ "event": "levels", "mic": 0.42, "system": 0.18 }
{ "event": "permission.result", "value": "granted|microphoneDenied|screenRecordingNotReady" }
{ "event": "error", "scope": "capture|permission|protocol|stdin|sidecar", "code": "...", "message": "..." }
```

The full surface to be implemented across later phases (model management, library, export,
storage, retention) is in `../REBUILD_PLAN.md` section 4.

## Phase 1 acceptance and what to report back

Please run the build on your Mac and report:

1. The two `codesign -dv --verbose=4` blocks the script prints (confirms each identifier and
   designated requirement).
2. Which process the prompts and grants are attributed to. After granting, what name appears
   under System Settings, Privacy and Security, for both Microphone and Screen Recording: is it
   **MeetingAssistant Rebuild** (the app) or `meetingcore-sidecar`? This is the key result the
   spike exists to find.
3. The capture result: the output folder and the two `.caf` paths with non-zero byte sizes.
   Optionally `afinfo` on each file to confirm they are valid audio.
4. The `bundleId` and `pid` shown in the Sidecar panel (confirms the embedded sidecar identity).
5. Any error lines in the raw protocol log.

## Known fiddly bits (expected, will iterate on your report)

- The sidecar's `Info.plist` is embedded with a linker `-sectcreate` flag whose path is resolved
  relative to the sidecar package root. If `swift build` cannot find it, change the last linker
  argument in `sidecar/Package.swift` to an absolute path.
- If macOS attributes the grant to `meetingcore-sidecar` rather than to the app, or if the
  Screen Recording prompt does not appear at all, the documented fallback is to repackage the
  sidecar as a nested `LSUIElement` helper `.app` inside the bundle rather than a bare binary.
  This is a known fork the spike is meant to resolve; report point 2 above and I will adjust.
