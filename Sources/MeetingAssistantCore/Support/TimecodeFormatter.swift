import Foundation

public enum TimecodeFormatter {
  public static func string(from seconds: TimeInterval) -> String {
    guard seconds.isFinite else { return "00:00:00" }
    let totalSeconds = max(0, Int(seconds.rounded(.down)))
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60
    return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
  }
}

