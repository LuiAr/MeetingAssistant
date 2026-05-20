import Foundation

public struct AudioLevelSnapshot: Codable, Equatable, Sendable {
  public var system: Float
  public var microphone: Float

  public init(system: Float = 0, microphone: Float = 0) {
    self.system = system
    self.microphone = microphone
  }

  public mutating func set(_ value: Float, for source: AudioSource) {
    switch source {
    case .system:
      system = value
    case .microphone:
      microphone = value
    case .mixed:
      system = value
      microphone = value
    }
  }
}

