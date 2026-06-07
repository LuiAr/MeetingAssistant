# MeetingAssistant

MeetingAssistant is a native macOS app for recording meeting audio from your computer and microphone, transcribing it locally with Whisper (via [WhisperKit](https://github.com/argmaxinc/WhisperKit)), and saving an AI-ready Markdown transcript.

The app is designed for calls in apps such as Zoom, Google Meet, browsers, and similar meeting tools. It records system audio separately from microphone audio, shows live recording levels, supports pause/resume, transcribes after recording stops, and keeps a searchable library of past recordings.

The New Meeting screen uses the full window without the history sidebar. It shows up to three recent meetings that can be opened directly, plus a **Library** toolbar button that opens the most recent saved meeting.

## Saved Audio

Each meeting stores its available audio tracks inside its recording folder under `~/Documents/MeetingAssistant Recordings`. Use **Reveal audio files** from a meeting's More menu or sidebar context menu to select them in Finder for external transcription or processing.

When mixed audio is available it is selected first, followed by the separate computer-audio and microphone tracks.

## Storage Management

The Storage tab in Settings shows how much disk space saved meeting audio uses. Audio cleanup can be configured to:

- Never delete audio
- Delete audio after 7, 30, or 90 days
- Delete the oldest audio when total audio storage exceeds a selected limit

Automatic cleanup removes only audio files. Meeting metadata and transcripts are preserved.

Still in development
