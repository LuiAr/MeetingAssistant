# MeetingAssistant Rebuild Plan: from native SwiftUI to a web-stack hybrid

This document recommends how to rebuild MeetingAssistant so that features are faster and more pleasant to implement, and sets out how to guarantee that nothing the current app does is lost in the move.

It is written against your stated constraints: macOS only, transcription stays fully on-device (audio never leaves the Mac), and you want to build features in TypeScript/React.

## 1. The honest reality check

This app cannot become "fully non-native", and you should not try to make it. Two of its pillars are macOS-only native frameworks with no web equivalent:

- **System audio capture** uses ScreenCaptureKit. There is no browser or Node/Rust API that can record another app's audio on macOS. Every cross-platform meeting recorder that does this ships a native helper for exactly this reason.
- **On-device transcription** uses WhisperKit, which runs Whisper on CoreML and the Apple Neural Engine / GPU. Keeping audio on the Mac means keeping a native (or at least compiled C/C++/Rust) engine. A pure-web transcriber would be far slower and would not meet your privacy promise.

So the goal is not "remove native code". The goal is to **shrink native code to only the parts that genuinely need it, and rebuild everything else in the stack you enjoy.** The good news: the painful-to-iterate part of your app is the UI (~3,440 lines of SwiftUI views), and that is precisely the part that does not need to be native.

## 2. Recommended architecture

A **hybrid**: a React/TypeScript UI inside a lightweight shell, talking to a small headless Swift "core" that does only the native work.

```
+--------------------------------------------------------+
|  App shell (Tauri)                                     |
|                                                        |
|   +------------------------------+                     |
|   |  UI: React + TypeScript      |   <-- you build     |
|   |  (all Views/, rebuilt)       |       features here |
|   +--------------+---------------+                     |
|                  |  JSON over stdio / local socket     |
|   +--------------v---------------+                     |
|   |  meetingcore (Swift binary)  |   <-- reused from   |
|   |  ScreenCaptureKit capture    |       MeetingAssistantCore
|   |  WhisperKit transcription    |                     |
|   |  model download, permissions |                     |
|   |  file store, retention       |                     |
|   +------------------------------+                     |
+--------------------------------------------------------+
```

What changes and what stays:

- **Rebuild in React/TS:** every view. Sidebar/detail layout, onboarding wizard, settings, recorder panel, transcript reader, level meters, recent-meetings stack. This is where feature work becomes easy.
- **Keep as a Swift sidecar:** `MeetingAssistantCore` minus the views. Capture, transcription, model management, permissions, the file store, retention, and the Markdown/AI-context exporters. This is your hard-won, already-tested native logic.
- **Thin glue:** the shell starts the Swift core as a child process, sends it commands (start, pause, resume, stop, transcribe, list, rename, delete, export) and receives events (levels, progress, status, errors) as JSON.

### Why this shape

- It directly fixes your complaint. Feature velocity is gated by the UI layer, and that layer moves to a hot-reloading web stack.
- It protects the risky parts. You are not rewriting ScreenCaptureKit or WhisperKit integration, the two things most likely to break subtly.
- It keeps feature parity cheap (see section 5): the reused core carries its behaviour, and its existing unit tests, across unchanged.

## 3. Shell choice: Tauri vs Electron

**Recommendation: Tauri**, with Electron as the fallback if the team is heavily Node-centric and wants maximum ecosystem familiarity over footprint.

| Factor | Tauri | Electron |
| --- | --- | --- |
| UI | Any web framework (React/TS) | Any web framework (React/TS) |
| Renderer | System WebView (WKWebView on macOS) | Bundled Chromium |
| Bundle size | ~5-15 MB | ~120-180 MB |
| Backend language | Rust | Node.js |
| Spawning the Swift core | First-class "sidecar" binary support | `child_process.spawn` |
| Memory footprint | Low | Higher |
| Security model | Tight by default (explicit command allowlist) | Looser by default |
| Ecosystem / hiring | Smaller, growing | Very large, mature |

For a privacy-first, macOS-only, performance-sensitive app that already owns its native core, Tauri is the better technical fit: tiny bundles, a native WebView, and a built-in sidecar mechanism designed for exactly the "ship a helper binary" pattern you need. The Rust you write is thin glue (spawn the core, pass messages, read/write files), not heavy logic. Pick Electron only if Node familiarity outweighs the ~150 MB and the heavier runtime.

A note on the Swift core if you ever want zero new languages: you could instead keep the shell itself in Swift (a minimal AppKit window hosting a `WKWebView`) and load the React bundle into it. That avoids learning Rust entirely while still giving you the web UI. It is the most conservative option, but you lose Tauri's tooling, packaging, and auto-update conveniences. Tauri remains the recommendation; this is the escape hatch.

## 4. The native core boundary (sidecar contract)

Keep the core headless and communicate over a simple line-delimited JSON protocol. A sketch of the surface area, derived from your current services:

Commands (UI to core):

```
{ "cmd": "permissions.status" }
{ "cmd": "permissions.request", "kinds": ["microphone", "screen"] }
{ "cmd": "model.status" }
{ "cmd": "model.download", "modelId": "openai_whisper-large-v3-v20240930_turbo" }
{ "cmd": "model.setLocation", "path": "...", "move": true }
{ "cmd": "record.start", "micDeviceId": "...", "localeId": "en_GB" }
{ "cmd": "record.pause" }
{ "cmd": "record.resume" }
{ "cmd": "record.muteMic", "muted": true }
{ "cmd": "record.stop" }
{ "cmd": "library.list" }
{ "cmd": "library.rename", "id": "...", "title": "..." }
{ "cmd": "library.delete", "id": "..." }
{ "cmd": "library.revealAudio", "id": "..." }
{ "cmd": "export.markdown", "id": "..." }
{ "cmd": "export.aiContext", "id": "...", "options": { "date": true, "duration": true, "locale": false, "status": false, "files": false, "pauses": false } }
{ "cmd": "storage.setRecordingsRoot", "path": "...", "move": true }
{ "cmd": "storage.usage" }
{ "cmd": "storage.applyRetention" }
```

Events (core to UI):

```
{ "event": "levels", "mic": 0.42, "system": 0.18 }
{ "event": "status", "value": "recording" }
{ "event": "transcription.progress", "phase": "download|load|transcribe", "fraction": 0.6 }
{ "event": "permission.result", "value": "screenRecordingNotReady" }
{ "event": "error", "scope": "capture", "message": "..." }
{ "event": "library.changed" }
```

This contract is the single seam between the two worlds. If you define it carefully up front, the React side and the Swift side can be built and tested independently.

## 5. How feature parity is guaranteed

You asked specifically how to be sure every feature in today's app survives. There are four mechanisms, in order of strength.

1. **Reuse the tested core, do not rewrite it.** The behaviour that is hardest to re-derive (state machine, pause compaction, readiness gating, retention rules, export formats, transcriber edge cases) already lives in `MeetingAssistantCore` and is covered by unit tests. If the core moves into the sidecar unchanged, those behaviours move with it and the existing `swift test` suite keeps proving them. This converts most of the parity question from "re-implement and hope" into "keep and re-run tests".

2. **Keep the on-disk format identical.** Today a meeting is a folder containing `transcript.md`, `system.caf`, `microphone.caf`, optional `mixed.caf`, and a `RecordingDocument` (Codable JSON: `metadata`, `pauses`, `transcript`). If the rebuilt app reads and writes the same layout, then existing recordings open in the new app on day one, and every store/retention/export feature is exercised against real data rather than reconstructed. Treat the `RecordingDocument`, `RecordingMetadata`, `TranscriptSegment`, `PauseInterval`, `SpeakerLabel`, and `RecordingStatus` shapes as a frozen contract.

3. **The parity matrix in section 6 is the acceptance checklist.** Every user-facing feature and every non-obvious behaviour is enumerated and mapped to the source that implements it today. The rebuild is "done" only when every row is ticked. Nothing ships until the matrix is green.

4. **Behavioural regression on the seam.** For each command in the sidecar contract, write a small end-to-end check (record a short clip, stop, assert a transcript file and metadata appear; rename and assert; delete and assert; apply retention and assert audio gone but transcript kept). These catch parity drift that unit tests on either side individually would miss.

## 6. Feature parity matrix

Tick a row only when the rebuilt app reproduces the behaviour, including the subtle note. "Core (keep)" means the logic should be reused in the sidecar; "UI (rebuild)" means it is presentation to redo in React.

### Recording

| # | Feature / behaviour | Today's source | Layer | Done |
| --- | --- | --- | --- | --- |
| R1 | Capture system (computer) audio via ScreenCaptureKit, excluding the app's own audio | `SystemAudioCaptureService`, `ScreenCaptureContentProvider` | Core (keep) | [ ] |
| R2 | Capture microphone as a separate track; selectable input device | `MeetingRecorder`, `MicrophoneDeviceProvider` | Core (keep) | [ ] |
| R3 | Save mic and system as separate Core Audio (.caf) files | `CapturedAudioFileWriter`, `AudioSampleBufferHelpers` | Core (keep) | [ ] |
| R4 | Live input level meters for mic and system | `MeetingRecorder` levels, `LevelMeterView` | Core + UI | [ ] |
| R5 | Pause and resume; pauses recorded as intervals | `RecordingStateMachine`, `PauseInterval`, `PauseCompactor` | Core (keep) | [ ] |
| R6 | Mute microphone, recorded as silence to keep the timeline aligned | `MeetingRecorder` | Core (keep) | [ ] |
| R7 | Capture teardown cannot race in-flight file writes (mutate only on sampleQueue) | `SystemAudioCaptureService` | Core (keep) | [ ] |
| R8 | Recording status lifecycle: idle, requesting, recording, paused, finalizing, completed, failed | `RecordingStatus`, `RecordingStateMachine` | Core (keep) | [ ] |
| R9 | Recorder panel UI with controls and status | `RecorderPanelView` | UI (rebuild) | [ ] |

### Transcription

| # | Feature / behaviour | Today's source | Layer | Done |
| --- | --- | --- | --- | --- |
| T1 | On-device transcription with WhisperKit after recording stops; audio never uploaded | `WhisperKitTranscriber` | Core (keep) | [ ] |
| T2 | Default model `openai_whisper-large-v3-v20240930_turbo`; reused after download | `WhisperModelCatalog`, `WhisperKitTranscriber` | Core (keep) | [ ] |
| T3 | Locale mapped to a two-letter Whisper language code | `Locale+Default`, `WhisperKitTranscriber` | Core (keep) | [ ] |
| T4 | Download/load/transcribe progress surfaced to the UI | `MeetingRecorder.transcriptionProgress` | Core + UI | [ ] |
| T5 | Missing audio (silence) returns empty segments, not a fatal error | `WhisperKitTranscriber` | Core (keep) | [ ] |
| T6 | Non-fatal transcription errors preserved as warning segments at the end | `WhisperKitTranscriber` | Core (keep) | [ ] |
| T7 | Source-level speaker labels: You, Computer audio, Mixed | `SpeakerLabel` | Core (keep) | [ ] |

### Model management

| # | Feature / behaviour | Today's source | Layer | Done |
| --- | --- | --- | --- | --- |
| M1 | Download the model with progress, retry, offline/waiting-for-network handling | `ModelDownloadManager` | Core (keep) | [ ] |
| M2 | Model stored in a configurable location (default Application Support/MeetingAssistant/WhisperKit) | `ModelDownloadManager`, `StorageLocationPreferences` | Core (keep) | [ ] |
| M3 | Re-point model location at runtime, moving or re-downloading | `ModelDownloadManager.updateDownloadBase` | Core (keep) | [ ] |
| M4 | No model files ship in the bundle | packaging | Core (keep) | [ ] |

### Library and detail

| # | Feature / behaviour | Today's source | Layer | Done |
| --- | --- | --- | --- | --- |
| L1 | Searchable library of past meetings | `SidebarView`, `RecordingStore` | Core + UI | [ ] |
| L2 | Rename a meeting | `RecordingStore`, `SidebarView` | Core + UI | [ ] |
| L3 | Delete a meeting | `RecordingStore`, `SidebarView` | Core + UI | [ ] |
| L4 | Reveal audio files in Finder (mixed first, then computer, then mic) | `RecordingStore`, `SidebarView` | Core + UI | [ ] |
| L5 | Transcript reader: white card, capped reading width, speaker-grouped tinted blocks | `RecordingDetailView` | UI (rebuild) | [ ] |
| L6 | Metadata header: date, duration, speaker count, word count | `RecordingDetailView` | UI (rebuild) | [ ] |
| L7 | In-transcript search with match highlight and scroll-between-matches | `RecordingDetailView` | UI (rebuild) | [ ] |
| L8 | New Meeting is a full-window landing state with Go to Library | `ContentView` | UI (rebuild) | [ ] |
| L9 | New Meeting shows the three most recent meetings interactively | `RecentMeetingsStackView` | UI (rebuild) | [ ] |
| L10 | Fixed-width, non-resizable sidebar; gradient only on landing/onboarding | `ContentView`, `SidebarView`, `AppGradientBackground` | UI (rebuild) | [ ] |

### Export

| # | Feature / behaviour | Today's source | Layer | Done |
| --- | --- | --- | --- | --- |
| E1 | Markdown transcript export with timecoded, speaker-labelled lines | `MarkdownExporter` | Core (keep) | [ ] |
| E2 | One-click "Copy AI Context" to clipboard | `ContentView`, `MarkdownExporter.aiContext` | Core + UI | [ ] |
| E3 | Configurable AI-context detail: date, duration, locale, status, files, pauses | `RecordingDetailView` flags, `MarkdownExporter.AIContextOptions` | Core + UI | [ ] |
| E4 | Timecode formatting | `TimecodeFormatter` | Core (keep) | [ ] |

### Permissions and readiness

| # | Feature / behaviour | Today's source | Layer | Done |
| --- | --- | --- | --- | --- |
| P1 | Microphone and Screen Recording permissions requested and verified at preflight | `PermissionService` | Core (keep) | [ ] |
| P2 | No Speech Recognition permission needed (on-device Whisper) | `PermissionService` | Core (keep) | [ ] |
| P3 | Screen permission via CoreGraphics preflight/request, not SCK enumeration (avoids repeat prompts) | `PermissionService` | Core (keep) | [ ] |
| P4 | `screenRecordingNotReady` result drives actionable UI (Open Settings, Quit & Reopen) | `PermissionService`, `MeetingRecorder` | Core + UI | [ ] |
| P5 | Permission/model state refreshed on app reactivation (catches revocations / deleted model) | `ContentView` | Core + UI | [ ] |
| P6 | Recording gated until model on disk and both permissions authorised; Start says what is missing | `RecordingReadiness` | Core (keep) | [ ] |

### Onboarding

| # | Feature / behaviour | Today's source | Layer | Done |
| --- | --- | --- | --- | --- |
| O1 | Full-window first-run wizard: welcome, recordings location, model location, model download, permissions, finish | `OnboardingView` | UI (rebuild) | [ ] |
| O2 | Wizard cannot be skipped; each Continue is gated | `OnboardingView`, `OnboardingPreferences` | Core + UI | [ ] |
| O3 | Re-runnable from Settings > General (and DEBUG menu command) | `OnboardingView`, `SettingsView` | Core + UI | [ ] |
| O4 | Current step persisted so a relaunch (for Screen Recording) resumes the wizard | `OnboardingPreferences.step` | Core (keep) | [ ] |

### Settings, storage, retention

| # | Feature / behaviour | Today's source | Layer | Done |
| --- | --- | --- | --- | --- |
| S1 | Settings organised into General, Recordings, Transcription, Audio | `SettingsView` | UI (rebuild) | [ ] |
| S2 | Configurable recordings root (default ~/Documents/MeetingAssistant Recordings) | `StorageLocationPreferences`, `RecordingStore` | Core (keep) | [ ] |
| S3 | On change of root: prompt to move existing or use new location only | `RecordingStore.updateRootDirectory(to:moveExisting:)` | Core (keep) | [ ] |
| S4 | Unreachable folder (e.g. unplugged drive): clear warning + re-pick; `isRootDirectoryReachable`, `lastLoadError` | `RecordingStore` | Core + UI | [ ] |
| S5 | Audio storage accounting / usage display | `RecordingStore` | Core + UI | [ ] |
| S6 | Retention: never / 7 / 30 / 90 days / storage-limit; deletes audio only, keeps metadata + transcript | `AudioRetentionPolicy`, `RecordingStore` | Core (keep) | [ ] |
| S7 | Apply cleanup now | `RecordingStore`, `SettingsView` | Core + UI | [ ] |
| S8 | Preserved UserDefaults keys (so settings carry over): `recordingsDirectoryPath`, `modelDirectoryPath`, `hasCompletedOnboarding`, `onboardingStep`, `audioRetentionPolicy`, `audioStorageLimitBytes`, `selectedMicrophoneDeviceID`, `aiContextInclude*` | `StorageLocationPreferences`, `OnboardingPreferences`, `AudioStoragePreferences` | Core (keep) | [ ] |

### Platform, privacy, packaging

| # | Feature / behaviour | Today's source | Layer | Done |
| --- | --- | --- | --- | --- |
| X1 | macOS 15+ deployment; macOS 26-only APIs stay behind availability checks | `Package.swift`, views | Core + UI | [ ] |
| X2 | Stable app identity for TCC: pinned bundle identifier + designated requirement | `script/*`, packaging | Packaging | [ ] |
| X3 | Distinct dev vs release bundle identifiers so permissions never collide | `script/build_and_run.sh`, `script/package_release.sh` | Packaging | [ ] |
| X4 | Privacy: only outbound network is the one-time model download | architecture | Core (keep) | [ ] |
| X5 | Recordings/transcripts stored unencrypted in the chosen folder (FileVault guidance) | docs | Docs | [ ] |

## 7. The macOS permissions gotcha (read this before building)

This is the one thing most likely to bite a hybrid rebuild, so plan for it explicitly.

TCC permissions (Microphone, Screen Recording) attach to a code-signed identity. Today your scripts pin a bundle identifier and a designated requirement precisely so permissions stay stable across rebuilds. In the hybrid app, the process that actually calls ScreenCaptureKit and AVFoundation is the **Swift sidecar**, not the web shell. You must therefore:

- Embed the sidecar inside the app bundle and sign it as part of the same bundle, with the same team/identity and a stable designated requirement, exactly as `package_release.sh` does today.
- Verify which process macOS attributes the prompt and the grant to. With a properly embedded, co-signed helper the main app is normally the responsible process, but this must be tested early on a clean machine or a fresh TCC reset, not assumed.
- Keep the "freshly granted Screen Recording needs a relaunch" handling. That OS behaviour does not change in a hybrid app, and your `screenRecordingNotReady` flow already models it.

Prove permissions end to end in a throwaway spike (shell + sidecar, request both permissions, capture three seconds) before committing to the full rebuild. If permissions work in the spike, the rest is ordinary engineering.

## 8. Suggested migration phases

1. **Spike (de-risk).** Tauri shell + the existing Swift core compiled as a sidecar. Wire one command (`record.start`/`stop`) and prove system-audio capture, mic capture, and TCC permissions work end to end on a clean machine. This is the only phase that can kill the approach; do it first.
2. **Freeze the contracts.** Lock the sidecar JSON protocol (section 4) and the on-disk `RecordingDocument` format (section 5.2). Write the seam regression checks (section 5.4).
3. **Headless core.** Strip views from `MeetingAssistantCore`, expose the command/event loop, keep `swift test` green. No UI yet.
4. **UI vertical slices in React**, matrix section by section: library + detail first (read-only, lets you open existing recordings), then recorder panel, then onboarding, then settings.
5. **Parity pass.** Walk the whole matrix on a clean machine with real recordings copied in. Ship only when every row is ticked.
6. **Retire the SwiftUI app** once the rebuild reaches parity, keeping the old binary around until the new one has been used on real meetings for a while.

## 9. What you gain and what it costs

Gains: feature work moves to React/TS with hot reload and a huge component ecosystem; the UI is no longer entangled with capture/transcription; the heavy native logic stops being something you touch for routine features.

Costs: you introduce a process boundary (the sidecar protocol) and, with Tauri, a small amount of Rust glue; packaging gains a step (embed + co-sign the helper); and the permissions model needs the up-front spike. None of these touch the parts of the app that are hard to get right, which is the point.

## 10. Bottom line

Keep the native core, rebuild the UI. Use Tauri + React/TypeScript with your existing `MeetingAssistantCore` recompiled as an embedded, co-signed Swift sidecar. Guarantee parity by reusing the already-tested core, freezing the on-disk format so existing recordings carry over, and treating the section 6 matrix as the acceptance checklist. De-risk permissions with a spike before anything else.
