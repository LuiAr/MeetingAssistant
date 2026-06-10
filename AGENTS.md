# MeetingAssistant Agent Guide

## Project Shape

MeetingAssistant is a SwiftPM-based native macOS app. The executable target is intentionally small and delegates application UI and behavior to `MeetingAssistantCore` so models, stores, formatting, and state transitions are testable.

## Rules for Claude or Codex
- After I ask you to do anything on the project please always ask questions that would help you make sure you understood how things should be implemented.

## Build And Run

- The minimum deployment target is macOS 15 (`Package.swift` and the staged Info.plist). macOS 26-only APIs (for example `ToolbarSpacer`) must stay behind `if #available(macOS 26, *)`.
- Use `./script/build_and_run.sh` as the primary local entrypoint.
- Use `swift build` for compile checks.
- Use `swift test` for unit tests.
- The Codex Run button is wired through `.codex/environments/environment.toml`.
- `script/build_and_run.sh` signs the staged app bundle ad hoc with bundle identifier `devswift.MeetingAssistant` and an explicit designated requirement so macOS privacy permissions attach to a stable app identity during local development.
- Use `./script/build_and_run.sh --smoke-record 3` to launch the app bundle identity and attempt a short recording smoke test. The `--smoke-record` launch mode and `SmokeRecordView` are compiled only in DEBUG builds; release builds ignore the flag.

### App icons (dev vs release)

- Two icon sources live at the repo root. `app.icns` / `app.iconset` is the clean release icon. `app-dev.iconset` is the same icon with an orange rounded-rectangle border, used to tell development builds apart in the Dock and app switcher. The source iconset PNGs are full-bleed opaque squares (macOS applies the rounded mask at display time), so the dev border is drawn as an inset rounded-rect frame rather than tracing the alpha edge.
- `script/build_and_run.sh` stages the dev icon: it prefers `app-dev.icns` / `app-dev.iconset` and falls back to `app.icns` / `app.iconset` if the dev assets are absent. It runs `iconutil` to build the `.icns` from the iconset at build time. To regenerate the dev icon, rebuild `app-dev.iconset` from `app.iconset` (orange border overlay) and rerun the script.

### Release packaging

- `script/package_release.sh` produces the distributable build: `swift build -c release`, staged into `dist/MeetingAssistant.app`, with the clean `app.icns`, ad-hoc signed with the release bundle identifier `com.devswift.MeetingAssistant` (deliberately distinct from the dev `devswift.MeetingAssistant` so their privacy permissions never collide), then zipped via `ditto`. Pass a version argument, e.g. `./script/package_release.sh 1.1.0`.
- The release bundle identifier and its pinned designated requirement keep TCC permissions stable across repackages. Never reuse the dev identifier for the release.
- Full packaging, GitHub Release, and Gatekeeper-bypass steps for downloaders are documented in `PACKAGING.html`.

## Architecture Notes

- `Sources/MeetingAssistant/App` contains the `@main` SwiftUI app entrypoint.
- `Sources/MeetingAssistantCore/Models` contains Codable recording and transcript data.
- `Sources/MeetingAssistantCore/Stores` owns local file persistence. The recordings root is user-configurable; defaults and resolution live in `Support/StorageLocationPreferences.swift` (default `~/Documents/MeetingAssistant Recordings`). `RecordingStore.updateRootDirectory(to:moveExisting:)` relocates recordings (moving existing folders without overwriting) and exposes `isRootDirectoryReachable` plus a `lastLoadError` when the folder's drive is unavailable.
- `RecordingStore` also owns saved-audio discovery, audio storage accounting, and audio-only retention cleanup.
- `Sources/MeetingAssistantCore/Services` owns ScreenCaptureKit capture, post-recording WhisperKit file transcription (`WhisperKitTranscriber`), permissions, Markdown export, and audio helpers. `ModelDownloadManager` resolves its download base from `StorageLocationPreferences` (default `~/Library/Application Support/MeetingAssistant/WhisperKit`) and can be re-pointed at runtime via `updateDownloadBase(to:moveExisting:)`.
- `Sources/MeetingAssistantCore/Views` contains SwiftUI views using a native sidebar/detail macOS layout. `OnboardingView` is the full-window first-run setup wizard; `SettingsView` is a sidebar/detail layout with General, Recordings, Transcription, and Audio sections. The library view is gradient-free (opaque sidebar, neutral detail pane); the gradient is used only on the New Meeting landing and onboarding. `RecordingDetailView` renders the transcript on a white content card with a capped reading width, speaker-grouped tinted blocks, a metadata header (date, duration, speaker count, word count), and in-transcript search that highlights matches and scrolls between them. The sidebar column is a fixed width (`navigationSplitViewColumnWidth(min:ideal:max:)` all equal) and non-resizable.
- The New Meeting landing state is full-window; the library sidebar/detail layout appears for saved and active meetings.
- `Sources/MeetingAssistantCore/Support` contains small formatting and timing helpers, the storage/onboarding preferences (`StorageLocationPreferences`, `OnboardingPreferences`), and the pure recording-readiness gate (`RecordingReadiness`).
- Root-level `app.icns` and `app.iconset` are the source app icon assets.

### First-run onboarding and gating

- On first launch `ContentView` shows `OnboardingView` until `OnboardingPreferences.isComplete` is set. The wizard cannot be skipped (each step's Continue button is gated) and is re-runnable from Settings ▸ General; in DEBUG builds the `Run Onboarding` menu command (⇧⌘O) does the same. Both call `OnboardingPreferences.reset()`. The current step is persisted under `OnboardingPreferences.stepKey` (via `OnboardingPreferences.step`/`setStep`) so the relaunch needed to apply Screen Recording resumes the wizard. The wizard renders on a translucent material card over the gradient for readability, with native step transitions and SF Symbol effects.
- Recording is gated by `RecordingReadiness`: the model must be on disk and both Microphone and Screen Recording must be authorised. The New Meeting Start button is disabled and its help text lists exactly what is missing; permission/model state is refreshed on `NSApplication.didBecomeActiveNotification` to catch revoked permissions or a deleted model.
- UserDefaults keys introduced: `recordingsDirectoryPath`, `modelDirectoryPath`, `hasCompletedOnboarding`, `onboardingStep` (existing keys: `audioRetentionPolicy`, `audioStorageLimitBytes`, `selectedMicrophoneDeviceID`, the `aiContextInclude*` flags).

## Recording Constraints

- System audio capture uses ScreenCaptureKit and excludes MeetingAssistant's own process audio.
- Microphone and system audio are saved separately as Core Audio files for reliable local transcription.
- Microphone and system audio permissions are required for recording. No Speech Recognition permission is needed — transcription is performed by WhisperKit running entirely on-device. Both microphone and system audio capture permissions are requested and verified during the preflight before recording starts.
- Screen/System Audio permission status uses CoreGraphics preflight/request APIs. Avoid using ScreenCaptureKit content enumeration as a permission preflight because it can repeatedly surface the privacy prompt.
- macOS only applies a freshly granted Screen Recording permission after the app relaunches. `requestRequiredPermissions()` returns a `PermissionRequestResult`; when it is `.screenRecordingNotReady` the UI shows actionable buttons (open System Settings, Quit & Reopen) instead of a generic error.
- Capture writers, handlers, and the write-failure callback in `SystemAudioCaptureService` are mutated only on `sampleQueue` so teardown cannot race an in-flight `AVAudioFile` write.
- Transcription runs after recording stops via WhisperKit on the saved CAF files (default model: `openai_whisper-large-v3-v20240930_turbo`). The model is downloaded during onboarding (or from Settings ▸ Transcription) into the configured model folder and reused thereafter; no model files ship in the app bundle.
- Locale identifiers are mapped to a Whisper two-letter language code via `Locale.language.languageCode` before being passed to `DecodingOptions.language`.
- `MeetingRecorder.transcriptionProgress` exposes download/load/transcribe progress; the recorder panel renders a `TranscriptionProgressBanner` while it is non-nil.
- If an audio file is missing (e.g., due to complete silence/lack of write buffers), the transcriber returns empty segments instead of throwing a fatal error.
- Non-fatal transcription errors are preserved and appended as warning segments at the end of the final transcript instead of being swallowed.
- Speaker labels are source-level only in v1: `You`, `Computer audio`, or `Mixed`.
- Protected or DRM media may not be available through macOS capture APIs.
- Every saved meeting can reveal its available audio files in Finder. Mixed audio is preferred when present, followed by the separate computer and microphone tracks.
- Audio retention policies can automatically remove audio after 7/30/90 days or when total audio storage exceeds a configured limit. Cleanup preserves meeting metadata and transcripts.

## Change Rules

Update this file when changing architecture, tooling, release workflow, recording/transcription strategy, or known capture limitations.

Update `README.md` when changing user-facing behavior, setup steps, permissions, saved file layout, transcript format, or known limitations.


## Implementation Plan

- [x] Expose saved meeting audio files in Finder for external transcription.
- [x] Add audio storage accounting and automatic audio-only retention policies.
- [x] Make New Meeting a full-window state with a Go to Library action.
- [x] Show an interactive list of the three most recent meetings on New Meeting.
- [x] Add a full-window first-run onboarding wizard (welcome, locations, model download, permissions) that is skippable and re-runnable from Settings.
- [x] Make recordings and model storage locations user-configurable with move-or-keep / move-or-re-download prompts.
- [x] Gate recording on the model being on disk and both permissions authorised, with Start help text naming what is missing.
