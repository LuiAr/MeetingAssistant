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
      #if DEBUG
      if case .smokeRecord(let seconds) = launchMode {
        SmokeRecordView(seconds: seconds)
          .frame(width: 460, height: 260)
      } else {
        ContentView()
          .frame(minWidth: 980, minHeight: 640)
      }
      #else
      ContentView()
        .frame(minWidth: 980, minHeight: 640)
      #endif
    }
    .defaultSize(width: 1280, height: 860)
    // Clamp the window's minimum size to the content's minimum so it can't be
    // resized shorter than 640pt. Without this, the window could shrink below the
    // content's min height; SwiftUI then keeps the content at 640pt and centers the
    // overflow, sliding the top (sidebar search field) up under the title bar.
    .windowResizability(.contentMinSize)
    .commands {
      CommandGroup(after: .newItem) {
        Button("Refresh Recordings") {
          NotificationCenter.default.post(name: .meetingAssistantRefreshRecordings, object: nil)
        }
        .keyboardShortcut("r", modifiers: [.command])

        #if DEBUG
        Button("Insert Sample Long Recording") {
          Task { @MainActor in
            try? AppSession.shared.store.insertSampleLongRecording()
          }
        }

        Button("Run Onboarding") {
          OnboardingPreferences.reset()
        }
        .keyboardShortcut("o", modifiers: [.command, .shift])
        #endif
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
    // The smoke-record harness is a development-only affordance. Release builds ignore the
    // flag entirely so a shipped app can never be launched into an automated recording.
    #if DEBUG
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: "--smoke-record") else {
      return .normal
    }

    let seconds = arguments.indices.contains(index + 1)
      ? Int(arguments[index + 1]) ?? 3
      : 3
    return .smokeRecord(seconds: max(1, min(30, seconds)))
    #else
    return .normal
    #endif
  }
}
