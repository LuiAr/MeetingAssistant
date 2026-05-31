import Foundation

/// Describes a WhisperKit model variant that the app could offer. Today the catalog only
/// ships one entry; the structure is in place so adding more (tiny/base/small/medium) and a
/// picker UI later is a localized change.
public struct WhisperModelVariant: Sendable, Identifiable, Equatable {
  public let id: String
  public let friendlyName: String
  public let approxDownloadBytes: Int64
  public let approxRAMBytes: Int64
  public let qualityTier: QualityTier
  public let summary: String
  public let recommendedMinRAMBytes: Int64

  public enum QualityTier: Int, Sendable, Comparable {
    case tiny, base, small, medium, large
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    public var displayName: String {
      switch self {
      case .tiny: return "Tiny"
      case .base: return "Base"
      case .small: return "Small"
      case .medium: return "Medium"
      case .large: return "Large"
      }
    }
  }
}

public enum WhisperModelCatalog {
  /// Ordered roughly from smallest/fastest to largest/best quality.
  public static let all: [WhisperModelVariant] = [
    WhisperModelVariant(
      id: "openai_whisper-large-v3-v20240930_turbo",
      friendlyName: "Large v3 Turbo",
      approxDownloadBytes: 1_620_000_000,
      approxRAMBytes: 2_400_000_000,
      qualityTier: .large,
      summary: "Best transcription quality with the fast turbo decoder. Suited to Apple Silicon Macs with 16 GB or more of unified memory.",
      recommendedMinRAMBytes: 8_000_000_000
    )
  ]

  public static var hostPhysicalMemoryBytes: Int64 {
    Int64(ProcessInfo.processInfo.physicalMemory)
  }

  /// Returns the highest-quality variant whose recommended-RAM threshold fits this host.
  /// Falls back to the lowest-tier entry if nothing fits.
  public static func recommended(forHostBytes bytes: Int64 = hostPhysicalMemoryBytes) -> WhisperModelVariant {
    let sorted = all.sorted { $0.qualityTier < $1.qualityTier }
    let fitting = sorted.last { bytes >= $0.recommendedMinRAMBytes }
    return fitting ?? sorted.first ?? all[0]
  }

  public static func variant(withID id: String) -> WhisperModelVariant? {
    all.first { $0.id == id }
  }
}
