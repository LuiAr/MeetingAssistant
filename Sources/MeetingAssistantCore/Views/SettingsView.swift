import SwiftUI

public struct SettingsView: View {
  @AppStorage("recordingLocaleIdentifier") private var localeIdentifier = Locale.defaultRecordingLocaleIdentifier
  @AppStorage("selectedMicrophoneDeviceID") private var selectedMicrophoneDeviceID = ""
  @State private var microphones: [MicrophoneDevice] = []
  @State private var permissions = PermissionCenter()

  public init() {}

  public var body: some View {
    TabView {
      Form {
        Picker("Microphone", selection: $selectedMicrophoneDeviceID) {
          Text("System Default").tag("")
          ForEach(microphones) { microphone in
            Text(microphone.name).tag(microphone.id)
          }
        }

        TextField("Transcript Locale", text: $localeIdentifier)

        LabeledContent("Recordings Folder") {
          Text(RecordingStore.defaultRootDirectory.path)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }
      .tabItem {
        Label("General", systemImage: "gearshape")
      }

      Form {
        PermissionRow(title: "Microphone", state: permissions.microphone)
        PermissionRow(title: "System Audio", state: permissions.systemAudio)

        Button("Request Permissions") {
          Task {
            _ = await permissions.requestRequiredPermissions()
            permissions.requestSystemAudioPermission()
          }
        }
      }
      .tabItem {
        Label("Permissions", systemImage: "lock")
      }
    }
    .frame(width: 560, height: 300)
    .scenePadding()
    .task {
      microphones = MicrophoneDeviceProvider.devices()
      permissions.refreshCachedStatuses()
    }
  }
}

private struct PermissionRow: View {
  var title: String
  var state: PermissionState

  var body: some View {
    LabeledContent(title) {
      Text(label)
        .foregroundStyle(color)
    }
  }

  private var label: String {
    switch state {
    case .authorized:
      return "Authorized"
    case .denied:
      return "Denied"
    case .restricted:
      return "Restricted"
    case .unknown:
      return "Unknown"
    }
  }

  private var color: Color {
    switch state {
    case .authorized:
      return .green
    case .denied, .restricted:
      return .red
    case .unknown:
      return .secondary
    }
  }
}
