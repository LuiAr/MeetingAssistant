import Foundation
import ScreenCaptureKit

public enum ScreenCaptureContentProvider {
  public static func current() async throws -> SCShareableContent {
    try await withCheckedThrowingContinuation { continuation in
      SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
        if let content {
          continuation.resume(returning: content)
        } else {
          continuation.resume(throwing: error ?? CaptureServiceError.noShareableContent)
        }
      }
    }
  }

  public static func currentProcess() async throws -> SCShareableContent {
    try await withCheckedThrowingContinuation { continuation in
      SCShareableContent.getCurrentProcessShareableContent { content, error in
        if let content {
          continuation.resume(returning: content)
        } else {
          continuation.resume(throwing: error ?? CaptureServiceError.noShareableContent)
        }
      }
    }
  }
}

public enum CaptureServiceError: LocalizedError {
  case noShareableContent
  case noDisplay
  case captureUnavailable
  case audioFileUnavailable

  public var errorDescription: String? {
    switch self {
    case .noShareableContent:
      return "ScreenCaptureKit could not enumerate shareable content."
    case .noDisplay:
      return "No display is available for system audio capture."
    case .captureUnavailable:
      return "Audio capture is unavailable."
    case .audioFileUnavailable:
      return "The audio file could not be opened for transcription."
    }
  }
}
