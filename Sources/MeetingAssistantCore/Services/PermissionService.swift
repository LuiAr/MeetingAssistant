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

  public func requestRequiredPermissions() async -> Bool {
    microphone = await requestMicrophone()
    if Self.systemAudioStatus() != .authorized {
      requestSystemAudioPermission()
    } else {
      systemAudio = .authorized
    }
    return microphone == .authorized && systemAudio == .authorized
  }

  public func requestSystemAudioPermission() {
    systemAudio = CGRequestScreenCaptureAccess() || CGPreflightScreenCaptureAccess()
      ? .authorized
      : .denied
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
