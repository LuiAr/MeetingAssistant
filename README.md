# MeetingAssistant

MeetingAssistant is a native macOS app for recording meeting audio from your computer and microphone, transcribing it locally with Whisper (via [WhisperKit](https://github.com/argmaxinc/WhisperKit)), and saving an AI-ready Markdown transcript.

It is designed for calls in apps such as Zoom, Google Meet, browsers, and similar meeting tools. It records system audio separately from microphone audio, shows live recording levels, supports pause and resume, transcribes after recording stops, and keeps a searchable library of past recordings.

Everything happens on your Mac. The only time the app reaches the network is to download the transcription model once (see Privacy below).

## Features

- Records computer (system) audio and your microphone as separate tracks.
- On-device transcription with WhisperKit, no audio ever leaves your Mac.
- Live input level meters, pause and resume, and microphone mute (recorded as silence to keep the timeline aligned).
- Searchable library of past meetings with rename, delete, and Finder reveal.
- One-click "Copy AI Context" to paste a meeting into an assistant, with configurable detail.
- Markdown transcript export with timecoded, speaker-labelled lines.
- Storage management with automatic, audio-only retention policies.

## Requirements

- macOS 15 (Sequoia) or later. Per-app audio capture relies on ScreenCaptureKit APIs introduced in macOS 15.
- Apple Silicon is recommended for fast on-device transcription. 16 GB of unified memory or more is recommended for the default large model.
- About 1.6 GB of free disk space for the transcription model, downloaded on first use.
- A Swift 6.2 toolchain (Xcode 16 or later, or a matching Swift toolchain) to build from source.

## Privacy

- Transcription runs entirely on-device with WhisperKit. Audio and transcripts are never uploaded.
- The only outbound network connection is the one-time download of the Whisper model from the `argmaxinc/whisperkit-coreml` repository on Hugging Face. The app also performs lightweight reachability checks while downloading; no personal data is sent.
- Recordings and transcripts are stored unencrypted on disk in your chosen recordings folder (by default `~/Documents/MeetingAssistant Recordings`). Protect them with full-disk encryption (FileVault) if the contents are sensitive.
- Recording other people may require their consent depending on your jurisdiction and the nature of the meeting. You are responsible for obtaining any consent that applies to you.

## Building from source

```bash
git clone <your-fork-url>
cd MeetingAssistant
swift build
swift test
```

To produce and launch a runnable `.app` bundle (staged under `dist/`, ad-hoc signed for stable local privacy permissions):

```bash
./script/build_and_run.sh
```

See `PACKAGING.html` in this repository for a step-by-step guide to packaging a release and installing it past Gatekeeper, including how to run a development build and a released build side by side.

## First run

On first launch a short setup wizard guides you through everything recording needs. It must be completed before you can record, and you can run it again at any time from **Settings ▸ General ▸ Re-run setup**.

1. **Welcome and privacy.** A summary of what the app does and a note that everything is on-device.
2. **Recordings location.** Choose where meetings are saved. The default is `~/Documents/MeetingAssistant Recordings`; you can pick any folder.
3. **Model location.** Choose where the transcription model is stored. The default is `~/Library/Application Support/MeetingAssistant/WhisperKit`. The model is about 1.6 GB, so an external drive is supported.
4. **Download the model.** Progress, retry, and offline handling are shown. You cannot continue until the model is on disk.
5. **Permissions.** Grant **Microphone**, then **Screen Recording**. macOS only applies a freshly granted Screen Recording permission after the app relaunches, so the wizard offers **Open Settings** and **Quit & Reopen**; the wizard resumes where you left off after relaunching.
6. **Finish.** You land on New Meeting, ready to record.

Recording is impossible until the model is on disk and both Microphone and Screen Recording are authorised. While anything is still missing, the **Start Recording** button stays disabled and says exactly what is needed, with a **Finish setup** shortcut back into the wizard.

## Saved audio

Each meeting stores its available audio tracks inside its recording folder under your chosen recordings location (by default `~/Documents/MeetingAssistant Recordings`). Use **Reveal audio files** from a meeting's More menu or sidebar context menu to select them in Finder for external transcription or processing. When mixed audio is available it is selected first, followed by the separate computer-audio and microphone tracks.

## Storage locations

Settings is organised into **General**, **Recordings**, **Transcription**, and **Audio**.

- **Recordings** lets you change where meetings are saved. When you pick a new folder you are asked whether to move the recordings already saved there or to use the new location only, so nothing is lost silently. If a chosen folder later becomes unavailable (for example an external drive is unplugged), the app shows a clear warning and a way to re-pick.
- **Transcription** lets you change where the model is stored. Changing the location offers to move the existing model or to download it again at the new location, and re-points WhisperKit accordingly.

## Storage management

The **Recordings** tab in Settings shows how much disk space saved meeting audio uses. Audio cleanup can be configured to never delete audio, delete audio after 7, 30, or 90 days, or delete the oldest audio when total audio storage exceeds a selected limit. Automatic cleanup removes only audio files; meeting metadata and transcripts are always preserved.

## Licence

MeetingAssistant is released under the MIT License (see `LICENSE`). Third-party components and the transcription model are credited in `THIRD_PARTY_NOTICES.md`.
