import Foundation

/// Pure description of whether the app is ready to record. Recording must be impossible until
/// the transcription model is on disk and both Microphone and Screen Recording permissions are
/// authorised. This type computes that gate and the exact "what is still missing" text, with no
/// UI or service dependencies so it can be unit-tested directly.
public struct RecordingReadiness: Equatable, Sendable {
  public let modelReady: Bool
  public let microphoneAuthorised: Bool
  public let screenRecordingAuthorised: Bool

  public init(modelReady: Bool, microphoneAuthorised: Bool, screenRecordingAuthorised: Bool) {
    self.modelReady = modelReady
    self.microphoneAuthorised = microphoneAuthorised
    self.screenRecordingAuthorised = screenRecordingAuthorised
  }

  public var canRecord: Bool {
    modelReady && microphoneAuthorised && screenRecordingAuthorised
  }

  /// The outstanding requirements, in the order they are presented during onboarding.
  public var missingRequirements: [String] {
    var missing: [String] = []
    if !modelReady {
      missing.append("the transcription model")
    }
    if !microphoneAuthorised {
      missing.append("Microphone access")
    }
    if !screenRecordingAuthorised {
      missing.append("Screen Recording access")
    }
    return missing
  }

  /// Help text for the Start button. `nil` when everything is ready.
  public var startButtonHelp: String? {
    let missing = missingRequirements
    guard !missing.isEmpty else { return nil }
    return "Finish setup first: \(Self.sentence(from: missing)) \(missing.count == 1 ? "is" : "are") still needed before recording."
  }

  /// Joins items into a natural-language list, for example "A, B and C".
  static func sentence(from items: [String]) -> String {
    switch items.count {
    case 0:
      return ""
    case 1:
      return items[0]
    case 2:
      return "\(items[0]) and \(items[1])"
    default:
      let head = items.dropLast().joined(separator: ", ")
      return "\(head) and \(items[items.count - 1])"
    }
  }
}
