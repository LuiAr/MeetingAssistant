# Frozen contracts (Phase 2)

This file is the single source of truth for the two seams of the rebuild: the sidecar JSON
protocol and the on-disk recording format. Changing anything here is a breaking change and
requires bumping the protocol version and a deliberate review. The TypeScript mirror lives in
`app/src/contract.ts`; the Swift reference shapes live in the root package
(`Sources/MeetingAssistantCore/Models/`) and must not be modified. The seam regression tests
in `sidecar/Tests/SeamTests/` enforce this document against the built sidecar.

## 1. Transport

NDJSON (one JSON object per line) over the sidecar's stdin/stdout. stdout is protocol only.
stderr is human-readable logging only and must never be parsed. The sidecar exits 0 when its
stdin reaches EOF (the shell quit). Current protocol version: **1**.

```
Command:   { "id": "c1", "cmd": "name", ...params }
Response:  { "id": "c1", "ok": true, "result": {...} }
           { "id": "c1", "ok": false, "error": { "code": "...", "message": "..." } }
Event:     { "event": "name", ...fields }
```

Rules:

- Every command gets exactly one response, with the caller's `id` echoed back.
- Events are unsolicited and may interleave with responses in any order.
- A line that cannot be decoded as a command produces an `error` event with scope
  `protocol` and code `badRequest` (no response, since there is no usable `id`).
- Unknown or not-yet-implemented commands respond `ok: false` with code `unsupportedCommand`.
- Blank lines are ignored.

## 2. Commands

All commands below are implemented as of Phase 3. Two naming resolutions against the plan's
sketch in `REBUILD_PLAN.md` section 4: recording references use `recordingId` (because `id`
is taken by the command envelope), and `record.start`'s Phase 1 `outputDir` parameter is now
ignored with a stderr note (the recordings root governs; use `storage.setRecordingsRoot`).

### Permissions and recording

`permissions.status`

```
-> { "id": "c1", "cmd": "permissions.status" }
<- { "id": "c1", "ok": true, "result": { "microphone": <PermissionState>, "screen": <PermissionState> } }
```

`permissions.request`

```
-> { "id": "c2", "cmd": "permissions.request", "kinds": ["microphone", "screen"] }
<- { "id": "c2", "ok": true, "result": { "microphone": <PermissionState>, "screen": <PermissionState>, "result": <PermissionRequestResult> } }
```

`kinds` is optional and defaults to both. A `permission.result` event is emitted before the
response.

`record.start`

```
-> { "id": "c3", "cmd": "record.start", "title": "...", "localeId": "en-GB", "micDeviceId": "..." }
<- { "id": "c3", "ok": true, "result": { "recordingId": "UUID", "folderName": "...", "outputDir": "...", "title": "...", "localeId": "...", "systemAudioPath": "...", "microphoneAudioPath": "..." } }
```

All parameters optional: `title` defaults to "Meeting <date>", `localeId` to the system
locale, `micDeviceId` to the default input. Starts the real `MeetingRecorder` flow: a draft
`recording.json` is created in the recordings root and capture begins. Requires the Whisper
model on disk and both permissions; failures respond `startFailed` (with a
`permission.result` event when caused by permissions). Other errors: `alreadyRecording`.

`record.pause` / `record.resume`

```
-> { "id": "c4", "cmd": "record.pause" }
<- { "id": "c4", "ok": true, "result": { "status": "paused" } }
```

Pauses are recorded as `PauseInterval`s. Errors: `notRecording` (pause), `notPaused` (resume).

`record.muteMic`

```
-> { "id": "c5", "cmd": "record.muteMic", "muted": true }
<- { "id": "c5", "ok": true, "result": { "muted": true } }
```

Muted microphone audio is written as silence to keep the timeline aligned. `muted` defaults
to true. Error when idle: `notRecording`.

`record.stop`

```
-> { "id": "c6", "cmd": "record.stop" }
<- { "id": "c6", "ok": true, "result": { "recordingId": "UUID", "folderName": "...", "outputDir": "...", "title": "...", "status": "completed", "durationSeconds": 12.3, "activeDurationSeconds": 11.1, "transcriptSegments": 4, "systemAudioPath": "...", "systemBytes": 123, "microphoneAudioPath": "...", "microphoneBytes": 456 } }
```

Stop finalises the recording and transcribes on-device before responding, so the response
can take minutes (`transcription.progress` events stream meanwhile; commands are dispatched
concurrently, so the sidecar stays responsive). Emits `library.changed` on success. Errors:
`notRecording`, `stopFailed`.

### Model

`model.status`

```
-> { "id": "m1", "cmd": "model.status" }
<- { "id": "m1", "ok": true, "result": { "value": <ModelStatusValue>, "modelId": "...", "modelPath": "...", "isOnDisk": true, "fraction"?, "attempt"?, "message"?, "onDiskBytes"? } }
```

`model.download`

```
-> { "id": "m2", "cmd": "model.download", "modelId": "...optional..." }
<- { "id": "m2", "ok": true, "result": { "started": true, "modelId": "..." } }
```

Responds immediately; progress arrives as `model.status` events. A `modelId` other than the
single catalog entry is rejected with `badRequest`.

`model.setLocation`

```
-> { "id": "m3", "cmd": "model.setLocation", "path": "/abs/dir", "move": true }
<- { "id": "m3", "ok": true, "result": { "downloadBase": "...", "modelPath": "...", "isOnDisk": true } }
```

### Library

`library.list`

```
-> { "id": "l1", "cmd": "library.list" }
<- { "id": "l1", "ok": true, "result": { "recordings": [ <RecordingMetadata + "hasAudio": bool> ], "rootDir": "...", "audioStorageBytes": 123, "warning"? } }
```

Metadata objects use the exact on-disk field names (section 5) with ISO8601 dates. `warning`
is present when the recordings root is unreachable.

`library.document` (added in Phase 3; the detail view needs the full document)

```
-> { "id": "l2", "cmd": "library.document", "recordingId": "UUID" }
<- { "id": "l2", "ok": true, "result": <RecordingDocument> }
```

`library.rename`

```
-> { "id": "l3", "cmd": "library.rename", "recordingId": "UUID", "title": "New title" }
<- { "id": "l3", "ok": true, "result": { "recordingId": "UUID", "title": "New title" } }
```

`library.delete`

```
-> { "id": "l4", "cmd": "library.delete", "recordingId": "UUID" }
<- { "id": "l4", "ok": true, "result": { "deleted": true } }
```

`library.revealAudio`

```
-> { "id": "l5", "cmd": "library.revealAudio", "recordingId": "UUID" }
<- { "id": "l5", "ok": true, "result": { "revealed": true } }
```

Reveals in Finder (mixed first, then computer, then mic). `revealed` is false when the
recording has no audio files (after retention). Rename, delete and the storage commands
below emit `library.changed`. Common library errors: `badRequest` (missing/invalid
`recordingId`), `notFound`.

### Export

`export.markdown`

```
-> { "id": "e1", "cmd": "export.markdown", "recordingId": "UUID" }
<- { "id": "e1", "ok": true, "result": { "markdown": "..." } }
```

`export.aiContext`

```
-> { "id": "e2", "cmd": "export.aiContext", "recordingId": "UUID", "options": { "date": true, "duration": true, "locale": false, "status": false, "files": false, "pauses": false } }
<- { "id": "e2", "ok": true, "result": { "text": "..." } }
```

All option flags are optional and default to the core's `AIContextOptions` defaults (date
and duration on, the rest off).

### Storage

`storage.setRecordingsRoot`

```
-> { "id": "s1", "cmd": "storage.setRecordingsRoot", "path": "/abs/dir", "move": true }
<- { "id": "s1", "ok": true, "result": { "rootDir": "..." } }
```

`move` defaults to false. Moving never overwrites; name collisions are left in place.
Setting the default path clears the stored override.

`storage.usage`

```
-> { "id": "s2", "cmd": "storage.usage" }
<- { "id": "s2", "ok": true, "result": { "rootDir": "...", "audioStorageBytes": 123, "recordings": 5, "isReachable": true, "retentionPolicy": "never", "storageLimitBytes": 5000000000 } }
```

`storage.setRetention` (added in Phase 3; the UI cannot write the sidecar's defaults domain
directly, so retention is configured through the seam)

```
-> { "id": "s3", "cmd": "storage.setRetention", "policy": "after30Days", "limitBytes": 5000000000 }
<- { "id": "s3", "ok": true, "result": { "retentionPolicy": "...", "storageLimitBytes": 123 } }
```

`policy` is an `AudioRetentionPolicy` raw value (section 6); `limitBytes` is optional.

`storage.applyRetention`

```
-> { "id": "s4", "cmd": "storage.applyRetention" }
<- { "id": "s4", "ok": true, "result": { "audioStorageBytes": 123, "retentionPolicy": "..." } }
```

Deletes audio only per the configured policy; metadata and transcripts are kept.

## 3. Events

```
{ "event": "ready", "protocol": 1, "sidecar": "0.2.0", "pid": 1234, "bundleId": "com.devswift.MeetingAssistant.rebuild.sidecar" }
{ "event": "levels", "mic": 0.42, "system": 0.18 }
{ "event": "status", "value": <RecordingStatus> }
{ "event": "permission.result", "value": <PermissionRequestResult> }
{ "event": "transcription.progress", "phase": "download" | "load" | "transcribe", "fraction": 0.6, "model": "..." }
{ "event": "model.status", "value": <ModelStatusValue>, "fraction"?, "attempt"?, "message"? }
{ "event": "library.changed" }
{ "event": "error", "scope": "...", "code": "...", "message": "..." }
```

- `ready` is always the first line on stdout after launch.
- `levels` values are 0.0 to 1.0 floats, emitted only while recording or paused, at most
  roughly every 120 ms (the state poll interval).
- `status` covers the full `RecordingStatus` set (section 5), emitted on every change.
- `transcription.progress` has `fraction` for the download and transcribe phases only.
- `model.status` is emitted whenever the model manager's state changes (Phase 3 addition;
  download progress arrives this way).
- `library.changed` follows record.stop, rename, delete, setRecordingsRoot, applyRetention.

Error scopes seen today: `protocol`, `stdin`, `capture`, plus `sidecar` synthesised by the
Rust shell when the sidecar's stdout closes (`code: "eof"`).

## 4. Enumerated values

`PermissionState` (source: `PermissionService.swift`):
`unknown` | `authorized` | `denied` | `restricted`

`PermissionRequestResult`:
`granted` | `microphoneDenied` | `screenRecordingNotReady`

`ModelStatusValue` (source: `ModelDownloadManager.ModelStatus`):
`unknown` | `notDownloaded` | `downloading` | `waitingForNetwork` | `downloaded` |
`loading` | `ready` | `failed`

Error codes: `badRequest`, `unsupportedCommand`, `internal`, `alreadyRecording`,
`notRecording`, `notPaused`, `notFound`, `startFailed`, `stopFailed`, `writeFailure`,
`readFailed`, `eof`.

## 5. On-disk recording format

One folder per recording under the recordings root, containing:

| File | Notes |
| --- | --- |
| `recording.json` | The `RecordingDocument`, see below |
| `transcript.md` | Markdown transcript |
| `system.caf` | Optional after retention |
| `microphone.caf` | Optional after retention |
| `mixed.caf` | Optional |

`recording.json` is a `RecordingDocument` encoded by `JSONEncoder` with
`outputFormatting = [.prettyPrinted, .sortedKeys]` and `dateEncodingStrategy = .iso8601`
(decoded with `.iso8601`). The shapes, frozen exactly as the Swift `Codable` synthesis
produces them:

```
RecordingDocument {
  metadata: RecordingMetadata
  pauses: [PauseInterval]
  transcript: [TranscriptSegment]
}

RecordingMetadata {
  id: UUID string
  title: string
  createdAt: ISO8601 date
  startedAt: ISO8601 date
  endedAt: ISO8601 date (optional, key absent when nil)
  duration: seconds (number)
  activeDuration: seconds (number)
  localeIdentifier: string
  folderName: string
  transcriptFileName: string ("transcript.md")
  systemAudioFileName: string? ("system.caf")
  microphoneAudioFileName: string? ("microphone.caf")
  mixedAudioFileName: string? (optional)
  status: RecordingStatus
  errorMessage: string? (optional)
}

TranscriptSegment {
  id: UUID string
  startTime: seconds
  endTime: seconds (optional)
  speaker: SpeakerLabel
  text: string
  confidence: number (optional)
  isFinal: bool
}

PauseInterval {
  id: UUID string
  startedAt: ISO8601 date
  endedAt: ISO8601 date
  startOffset: seconds
  endOffset: seconds
}
```

`RecordingStatus` (string): `idle` | `requestingPermissions` | `recording` | `paused` |
`finalizing` | `completed` | `failed`

`SpeakerLabel` (string, note the human-readable raw values): `"You"` | `"Computer audio"` |
`"Mixed"`

## 6. UserDefaults keys (frozen)

| Key | Meaning |
| --- | --- |
| `recordingsDirectoryPath` | User-chosen recordings root |
| `modelDirectoryPath` | User-chosen model location |
| `hasCompletedOnboarding` | Onboarding done flag |
| `onboardingStep` | Resumable onboarding step |
| `audioRetentionPolicy` | `AudioRetentionPolicy` raw value: `never`, `after7Days`, `after30Days`, `after90Days`, `storageLimit` |
| `audioStorageLimitBytes` | Retention size cap, default 5,000,000,000 |
| `selectedMicrophoneDeviceID` | Preferred microphone input device |
| `aiContextIncludeDate`, `aiContextIncludeDuration`, `aiContextIncludeLocale`, `aiContextIncludeStatus`, `aiContextIncludeFiles`, `aiContextIncludePauses` | AI-context export flags |

Domain note (Phase 3 decision): the sidecar reads and writes these keys in its own defaults
domain (`com.devswift.MeetingAssistant.rebuild.sidecar`), not the native app's. Default
paths are identical, so the default library and model folder are shared with the native app;
custom-location overrides and other settings migrate with a one-time import when the native
app is retired. The UI configures sidecar-domain settings through the seam (for example
`storage.setRetention`), never by writing defaults directly.

## 7. Identities (frozen since Phase 1)

App `com.devswift.MeetingAssistant.rebuild`, sidecar
`com.devswift.MeetingAssistant.rebuild.sidecar`, both ad-hoc signed with pinned identifiers
and designated requirements. macOS attributes TCC permissions to the outer app (proven in
`PHASE1_REPORT.md`).
