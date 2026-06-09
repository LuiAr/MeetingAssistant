# Third-party notices

MeetingAssistant is distributed under the MIT License (see `LICENSE`). It builds on the
following open-source components, each under its own licence. Their copyrights remain with
their respective owners.

## Swift package dependencies

| Component | Project | Licence |
| --- | --- | --- |
| WhisperKit | https://github.com/argmaxinc/WhisperKit | MIT |
| swift-transformers | https://github.com/huggingface/swift-transformers | Apache-2.0 |
| swift-jinja | https://github.com/huggingface/swift-jinja | Apache-2.0 |
| swift-collections | https://github.com/apple/swift-collections | Apache-2.0 |
| swift-crypto | https://github.com/apple/swift-crypto | Apache-2.0 |
| swift-asn1 | https://github.com/apple/swift-asn1 | Apache-2.0 |
| swift-argument-parser | https://github.com/apple/swift-argument-parser | Apache-2.0 |
| yyjson | https://github.com/ibireme/yyjson | MIT |

Exact pinned versions are recorded in `Package.resolved`.

## Transcription model

Transcription uses an OpenAI Whisper model (default: `openai_whisper-large-v3-v20240930_turbo`),
downloaded at runtime from the `argmaxinc/whisperkit-coreml` repository on Hugging Face. The
Whisper models are released by OpenAI under the MIT License. No model weights are bundled with
this app; they are fetched on first use into the app's Application Support directory.

## Note on Apache-2.0 components

The Apache-2.0 licence requires that you retain its notice and any `NOTICE` file contents when
redistributing those components. When you publish binaries, include this file (or an equivalent
acknowledgements list) in the release.
