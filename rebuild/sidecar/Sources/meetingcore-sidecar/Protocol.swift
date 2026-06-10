import Foundation

// Frozen sidecar protocol (see ../../../CONTRACT.md). Line-delimited JSON (NDJSON) over stdio.
//
// UI to core (command):  { "id": "c1", "cmd": "name", ...params }
// core to UI (response): { "id": "c1", "ok": true, "result": {...} }
//                        { "id": "c1", "ok": false, "error": { "code": "...", "message": "..." } }
// core to UI (event):    { "event": "name", ...fields }
//
// stderr is reserved for human-readable logging and is never part of the protocol.
//
// Note on naming: the plan's sketch used "id" for recording references, but "id" is taken by
// the command envelope, so recording references use "recordingId" (documented in CONTRACT.md).

let protocolVersion = 1
let sidecarVersion = "0.2.0"
let sidecarBundleIdentifier = "com.devswift.MeetingAssistant.rebuild.sidecar"

/// Optional per-call overrides for the AI-context export. Missing flags fall back to the
/// core's `MarkdownExporter.AIContextOptions` defaults.
struct AIContextFlags: Decodable {
  let date: Bool?
  let duration: Bool?
  let locale: Bool?
  let status: Bool?
  let files: Bool?
  let pauses: Bool?
}

/// A decoded command envelope. Optional fields cover the full Phase 3 surface; unknown
/// commands are rejected with an `unsupportedCommand` error.
struct IncomingCommand: Decodable {
  let id: String
  let cmd: String
  let kinds: [String]?
  let outputDir: String?
  let micDeviceId: String?
  let title: String?
  let localeId: String?
  let muted: Bool?
  let modelId: String?
  let path: String?
  let move: Bool?
  let recordingId: String?
  let policy: String?
  let limitBytes: Int?
  let options: AIContextFlags?
}

/// A protocol error payload.
struct ProtocolError: Encodable {
  let code: String
  let message: String
}

enum SidecarError: Error {
  case message(code: String, text: String)
}
