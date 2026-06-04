import AppKit
import MeetingAssistantCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
  }
}

@main
struct MeetingAssistantApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  private let launchMode = AppLaunchMode.current

  var body: some Scene {
    WindowGroup("MeetingAssistant") {
      if case .smokeRecord(let seconds) = launchMode {
        SmokeRecordView(seconds: seconds)
          .frame(width: 460, height: 260)
      } else {
        ContentView()
          .frame(minWidth: 980, minHeight: 640)
      }
    }
    .commands {
      CommandGroup(after: .newItem) {
        Button("Refresh Recordings") {
          NotificationCenter.default.post(name: .meetingAssistantRefreshRecordings, object: nil)
        }
        .keyboardShortcut("r", modifiers: [.command])
      }
    }

    Settings {
      SettingsView()
    }
  }
}

private enum AppLaunchMode {
  case normal
  case smokeRecord(seconds: Int)

  static var current: AppLaunchMode {
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: "--smoke-record") else {
      return .normal
    }

    let seconds = arguments.indices.contains(index + 1)
      ? Int(arguments[index + 1]) ?? 3
      : 3
    return .smokeRecord(seconds: max(1, min(30, seconds)))
  }
}

