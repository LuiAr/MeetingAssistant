# MeetingAssistant

MeetingAssistant is a native macOS app for recording meeting audio from your computer and microphone, transcribing it locally with Whisper (via [WhisperKit](https://github.com/argmaxinc/WhisperKit)), and saving an AI-ready Markdown transcript.

The app is designed for calls in apps such as Zoom, Google Meet, browsers, and similar meeting tools. It records system audio separately from microphone audio, shows live recording levels, supports pause/resume, transcribes after recording stops, and keeps a searchable library of past recordings.

## Requirements

- macOS 26.0 or later
- Apple Silicon strongly recommended (WhisperKit runs on the Neural Engine)
- Xcode 26.5 or compatible Swift 6.3 toolchain
- Microphone permission for recording
- Screen/System Audio Recording permission for recording
- ~1.5 GB of free disk space for the Whisper model (downloaded once on first transcription)
- Internet connection for the first transcription only (model download); all subsequent transcriptions run fully offline

MeetingAssistant does not use a cloud transcription provider. Audio is transcribed entirely on-device with WhisperKit running the `openai_whisper-large-v3-v20240930_turbo` CoreML model. The model is downloaded from HuggingFace on first use into `~/Library/Application Support/argmaxinc/whisperkit/` (or `~/Library/Caches`, depending on WhisperKit version) and reused for every recording after that. To switch model, edit `WhisperKitTranscriber.defaultModel` in `Sources/MeetingAssistantCore/Services/WhisperKitTranscriber.swift`.

## Build And Run

From the project root:

```bash
./script/build_and_run.sh
```

Useful checks:

```bash
swift build
swift test
./script/build_and_run.sh --verify
```

The Codex app Run button is also wired to `./script/build_and_run.sh`.

The run script signs the local app bundle with the stable identifier `devswift.MeetingAssistant` so macOS privacy permissions are tied to the same app identity across local runs.

## First Launch

1. Open the app.
2. Go to Settings and confirm the microphone and transcript locale.
3. Click `Request Permissions` if permissions are not already authorized.
4. macOS may show permission prompts for microphone and screen/system audio capture.
5. If a permission is denied, open System Settings and grant access manually, then restart the app.
6. The first time you stop a recording, the app downloads the Whisper model (~1.5 GB). A progress bar appears in the recorder panel. Subsequent recordings reuse the cached model.

Microphone and system audio permissions are required to record. No Speech Recognition permission is needed — Whisper runs locally on your machine.

If macOS keeps asking for Screen & System Audio Recording after you have already approved it, remove old MeetingAssistant entries from System Settings, run the app again, and grant the prompt once. Older unsigned local builds may have registered a different temporary app identity.

## Recording A Meeting

1. Join your meeting in Zoom, Google Meet, a browser, or another meeting app.
2. In MeetingAssistant, enter a meeting title or leave it blank to use the default timestamped title.
3. Choose a microphone or keep `System Default`.
4. Click `Record`.
5. Watch the `Computer` and `Mic` meters to confirm audio is being captured.
6. Use `Pause` and `Resume` when needed. Paused time is excluded from transcript timecodes.
7. Click `Stop` to finalize the recording, run local Whisper transcription over the saved audio files, and save the transcript.

While recording, the app shows audio levels and elapsed time. Transcript generation starts after you stop recording, which keeps the recording path stable while Whisper processes the saved files. Expect transcription to take roughly 1/8th of the recording length on Apple Silicon with the default `large-v3-turbo` model.

## Past Recordings

Saved meetings appear in the sidebar. Selecting a meeting shows the generated Markdown transcript with metadata, pause intervals, file references, and timecoded transcript lines.

Available actions:

- `Copy Markdown`: copies the full saved transcript.
- `Copy AI Context`: copies an AI-friendly context block plus transcript.
- `Reveal`: opens the recording folder in Finder.
- `Share`: uses the macOS share sheet for the transcript file.
- Search: filters the selected transcript view.

## Saved Files

Recordings are stored here:

```text
~/Documents/MeetingAssistant Recordings/<recording-folder>/
```

Each recording folder contains:

- `recording.json`: structured metadata, pause intervals, and transcript data.
- `transcript.md`: AI-ready Markdown transcript.
- `system.caf`: captured computer audio.
- `microphone.caf`: captured microphone audio.

The app currently uses `.caf` audio files because they are reliable local inputs for WhisperKit transcription via AVFoundation.

## Transcript Format

Markdown transcripts include:

- YAML front matter with recording metadata.
- Meeting metadata and duration.
- Saved audio file references.
- Pause intervals.
- Timecoded transcript lines such as:

```markdown
[00:12:04] Computer audio: Let's review the launch plan.
[00:12:10] You: I can take the follow-up task.
```

Speaker labels are source-level only in this version:

- `You`: microphone-dominant audio.
- `Computer audio`: system/app audio.
- `Mixed`: uncertain or combined source.

MeetingAssistant does not yet perform true per-person speaker diarization.

## Known Limitations

- Protected or DRM audio may not be capturable by macOS.
- The first transcription requires a ~1.5 GB model download from HuggingFace.
- Transcript generation happens after recording stops and can take a few minutes for long meetings; a progress bar shows download and transcription progress.
- If the Whisper model fails to download or load, the app still saves audio files and records that no transcript was produced — re-stop the recording later to retry.
- Source-level labels do not identify individual remote meeting participants.
- Real meeting capture should be manually verified after permission or capture changes.

## Development Notes

The app icon is sourced from the root-level `app.icns` file. The `app.iconset` directory is kept as the editable icon source and fallback for regenerating the `.icns` bundle asset.

Keep this README updated when user-facing behavior changes, especially:

- Recording controls or permission flow
- Saved file names or folder layout
- Transcript Markdown format
- Transcription provider or locale behavior
- Known capture limitations
