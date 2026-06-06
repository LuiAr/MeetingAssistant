# MeetingAssistant Agent Guide

## Project Shape

MeetingAssistant is a SwiftPM-based native macOS app. The executable target is intentionally small and delegates application UI and behavior to `MeetingAssistantCore` so models, stores, formatting, and state transitions are testable.

## Rules for Claude or Codex
- After I ask you to do anything on the project please always ask questions that would help you make sure you understood how things should be implemented.

## Build And Run

- Use `./script/build_and_run.sh` as the primary local entrypoint.
- Use `swift build` for compile checks.
- Use `swift test` for unit tests.
- The Codex Run button is wired through `.codex/environments/environment.toml`.
- The app icon is staged by `script/build_and_run.sh` from root-level `app.icns`, with `app.iconset` as the fallback source.
- `script/build_and_run.sh` signs the staged app bundle ad hoc with bundle identifier `devswift.MeetingAssistant` and an explicit designated requirement so macOS privacy permissions attach to a stable app identity during local development.
- Use `./script/build_and_run.sh --smoke-record 3` to launch the app bundle identity and attempt a short recording smoke test.

## Architecture Notes

- `Sources/MeetingAssistant/App` contains the `@main` SwiftUI app entrypoint.
- `Sources/MeetingAssistantCore/Models` contains Codable recording and transcript data.
- `Sources/MeetingAssistantCore/Stores` owns local file persistence under `~/Documents/MeetingAssistant Recordings`.
- `Sources/MeetingAssistantCore/Services` owns ScreenCaptureKit capture, post-recording WhisperKit file transcription (`WhisperKitTranscriber`), permissions, Markdown export, and audio helpers.
- `Sources/MeetingAssistantCore/Views` contains SwiftUI views using a native sidebar/detail macOS layout.
- `Sources/MeetingAssistantCore/Support` contains small formatting and timing helpers.
- Root-level `app.icns` and `app.iconset` are the source app icon assets.

## Recording Constraints

- System audio capture uses ScreenCaptureKit and excludes MeetingAssistant's own process audio.
- Microphone and system audio are saved separately as Core Audio files for reliable local transcription.
- Microphone and system audio permissions are required for recording. No Speech Recognition permission is needed — transcription is performed by WhisperKit running entirely on-device. Both microphone and system audio capture permissions are requested and verified during the preflight before recording starts.
- Screen/System Audio permission status status uses CoreGraphics preflight/request APIs. Avoid using ScreenCaptureKit content enumeration as a permission preflight because it can repeatedly surface the privacy prompt.
- Transcription runs after recording stops via WhisperKit on the saved CAF files (default model: `openai_whisper-large-v3-v20240930_turbo`). The model is auto-downloaded on first use into WhisperKit's default cache directory and reused thereafter; no model files ship in the app bundle.
- Locale identifiers are mapped to a Whisper two-letter language code via `Locale.language.languageCode` before being passed to `DecodingOptions.language`.
- `MeetingRecorder.transcriptionProgress` exposes download/load/transcribe progress; the recorder panel renders a `TranscriptionProgressBanner` while it is non-nil.
- If an audio file is missing (e.g., due to complete silence/lack of write buffers), the transcriber returns empty segments instead of throwing a fatal error.
- Non-fatal transcription errors are preserved and appended as warning segments at the end of the final transcript instead of being swallowed.
- Speaker labels are source-level only in v1: `You`, `Computer audio`, or `Mixed`.
- Protected or DRM media may not be available through macOS capture APIs.

## Change Rules

Update this file when changing architecture, tooling, release workflow, recording/transcription strategy, or known capture limitations.

Update `README.md` when changing user-facing behavior, setup steps, permissions, saved file layout, transcript format, or known limitations.


## Implementation Plan

Update each step when it needs to (if its done, ongoing, etc....)