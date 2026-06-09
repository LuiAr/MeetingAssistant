import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import Observation

public enum PermissionState: String, Sendable {
  case unknown
  case authorized
  case denied
  case restricted
}

/// Outcome of a permission preflight before recording. `screenRecordingNotReady` covers both
/// "denied" and the macOS quirk where a freshly granted Screen Recording permission only
/// takes effect after the app is relaunched, because the remedy (enable in System Settings,
/// then quit and reopen) is the same in both cases.
public enum PermissionRequestResult: String, Sendable, Equatable {
  case granted
  case microphoneDenied
  case screenRecordingNotReady

  public var failureMessage: String? {
    switch self {
    case .granted:
      return nil
    case .microphoneDenied:
      return "Microphone access is needed to record what you say. Enable MeetingAssistant under System Settings ▸ Privacy & Security ▸ Microphone, then try again."
    case .screenRecordingNotReady:
      return "Screen Recording access is needed to capture computer audio. Enable MeetingAssistant under System Settings ▸ Privacy & Security ▸ Screen Recording, then quit and reopen the app. macOS only applies this permission after a relaunch."
    }
  }
}

@MainActor
@Observable
public final class PermissionCenter {
  public private(set) var microphone: PermissionState = .unknown
  public private(set) var systemAudio: PermissionState = .unknown

  public init() {
    refreshCachedStatuses()
  }

  public func refreshCachedStatuses() {
    microphone = Self.microphoneStatus()
    systemAudio = Self.systemAudioStatus()
  }

  /// True when both required permissions are authorised. Used to gate recording up front rather
  /// than discovering a missing permission only after the user taps Start.
  public var bothAuthorised: Bool {
    microphone == .authorized && systemAudio == .authorized
  }

  /// Requests Microphone access on its own, updating `microphone`. Used by the onboarding wizard
  /// so each permission can be requested and shown independently.
  public func requestMicrophonePermission() async {
    microphone = await requestMicrophone()
  }

  public func requestRequiredPermissions() async -> PermissionRequestResult {
    microphone = await requestMicrophone()
    guard microphone == .authorized else { return .microphoneDenied }

    if Self.systemAudioStatus() == .authorized {
      systemAudio = .authorized
      return .granted
    }

    requestSystemAudioPermission()
    return systemAudio == .authorized ? .granted : .screenRecordingNotReady
  }

  public func requestSystemAudioPermission() {
    systemAudio = CGRequestScreenCaptureAccess() || CGPreflightScreenCaptureAccess()
      ? .authorized
      : .denied
  }

  /// Opens System Settings at the Screen Recording privacy pane so the user can enable the
  /// app without hunting through the settings hierarchy.
  public func openScreenRecordingSettings() {
    open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
  }

  /// Opens System Settings at the Microphone privacy pane.
  public func openMicrophoneSettings() {
    open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
  }

  /// Launches a fresh instance of the app and terminates the current one. Used to apply a
  /// newly granted Screen Recording permission, which macOS only honours after a relaunch.
  public func relaunch() {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
      DispatchQueue.main.async {
        NSApplication.shared.terminate(nil)
      }
    }
  }

  private func open(_ urlString: String) {
    guard let url = URL(string: urlString) else { return }
    NSWorkspace.shared.open(url)
  }

  private func requestMicrophone() async -> PermissionState {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
      return .authorized
    case .denied:
      return .denied
    case .restricted:
      return .restricted
    case .notDetermined:
      let granted = await AVCaptureDevice.requestAccess(for: .audio)
      return granted ? .authorized : .denied
    @unknown default:
      return .unknown
    }
  }

  private static func microphoneStatus() -> PermissionState {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
      return .authorized
    case .denied:
      return .denied
    case .restricted:
      return .restricted
    case .notDetermined:
      return .unknown
    @unknown default:
      return .unknown
    }
  }

  private static func systemAudioStatus() -> PermissionState {
    CGPreflightScreenCaptureAccess() ? .authorized : .unknown
  }
}
