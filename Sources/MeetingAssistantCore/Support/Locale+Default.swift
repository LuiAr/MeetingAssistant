import Foundation

public extension Locale {
  static var defaultRecordingLocaleIdentifier: String {
    if #available(macOS 13.0, iOS 16.0, *) {
      let current = Locale.current
      let lang = current.language.languageCode?.identifier ?? "en"
      if let region = current.language.region?.identifier {
        return "\(lang)-\(region)"
      }
      return lang
    } else {
      let current = Locale.current
      let base = current.identifier.components(separatedBy: "@").first ?? current.identifier
      return base.replacingOccurrences(of: "_", with: "-")
    }
  }
}
