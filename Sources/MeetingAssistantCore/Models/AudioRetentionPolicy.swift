import Foundation

public enum AudioRetentionPolicy: String, CaseIterable, Identifiable, Sendable {
  case never
  case after7Days
  case after30Days
  case after90Days
  case storageLimit

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .never:
      return "Never"
    case .after7Days:
      return "After 7 days"
    case .after30Days:
      return "After 30 days"
    case .after90Days:
      return "After 90 days"
    case .storageLimit:
      return "When storage exceeds limit"
    }
  }

  public var ageInDays: Int? {
    switch self {
    case .after7Days:
      return 7
    case .after30Days:
      return 30
    case .after90Days:
      return 90
    case .never, .storageLimit:
      return nil
    }
  }
}

public enum AudioStoragePreferences {
  public static let policyKey = "audioRetentionPolicy"
  public static let storageLimitKey = "audioStorageLimitBytes"
  public static let defaultStorageLimitBytes = 5_000_000_000

  public static func policy(defaults: UserDefaults = .standard) -> AudioRetentionPolicy {
    guard let rawValue = defaults.string(forKey: policyKey) else { return .never }
    return AudioRetentionPolicy(rawValue: rawValue) ?? .never
  }

  public static func storageLimitBytes(defaults: UserDefaults = .standard) -> Int64 {
    guard defaults.object(forKey: storageLimitKey) != nil else {
      return Int64(defaultStorageLimitBytes)
    }
    return Int64(defaults.integer(forKey: storageLimitKey))
  }
}
