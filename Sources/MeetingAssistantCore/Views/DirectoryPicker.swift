import AppKit
import Foundation

/// Small wrapper around `NSOpenPanel` configured to choose a single directory. Shared by the
/// onboarding wizard and Settings so the recordings and model locations are picked the same way.
enum DirectoryPicker {
  static func chooseDirectory(message: String, prompt: String = "Choose") -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = prompt
    panel.message = message
    return panel.runModal() == .OK ? panel.url : nil
  }
}
