import Foundation

// Entry point for the headless capture/permission sidecar. Reads NDJSON commands from stdin,
// writes NDJSON responses and events to stdout, and exits cleanly when stdin reaches EOF
// (which happens when the Tauri shell that spawned it quits).

let io = SidecarIO()
io.emitReady()

Task { @MainActor in
  let controller = SidecarController(io: io)
  do {
    for try await line in FileHandle.standardInput.bytes.lines {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty { continue }
      guard let data = trimmed.data(using: .utf8),
            let command = try? JSONDecoder().decode(IncomingCommand.self, from: data) else {
        io.emitError(scope: "protocol", code: "badRequest", message: "Could not decode command line.")
        continue
      }
      // Dispatch rather than await: a long-running command (record.stop with transcription,
      // a model download) must not block the stdin command loop.
      controller.dispatch(command)
    }
  } catch {
    io.emitError(scope: "stdin", code: "readFailed", message: error.localizedDescription)
  }
  exit(0)
}

dispatchMain()
