import AppKit
import SwiftUI

/// The ordered steps of the first-run setup wizard.
enum OnboardingStep: Int, CaseIterable {
  case welcome
  case recordings
  case model
  case download
  case permissions
  case finish
}

/// Full-window first-run setup. Shown automatically until onboarding is marked complete, and
/// re-runnable from Settings. The wizard cannot be skipped: each step's Continue button stays
/// disabled until that step is satisfied. The current step is persisted so the relaunch needed
/// to apply a freshly granted Screen Recording permission resumes the wizard rather than
/// restarting it.
public struct OnboardingView: View {
  let onComplete: () -> Void

  @State private var step: OnboardingStep
  @State private var store = AppSession.shared.store
  @State private var recorder = AppSession.shared.recorder
  @State private var modelManager = ModelDownloadManager.shared

  @State private var recordingsDirectory = StorageLocationPreferences.recordingsDirectory()
  @State private var modelDirectory = StorageLocationPreferences.modelDirectory()
  @State private var locationError: String?

  @State private var appeared = false
  @State private var goingForward = true

  public init(onComplete: @escaping () -> Void) {
    self.onComplete = onComplete
    let raw = OnboardingPreferences.step()
    _step = State(initialValue: OnboardingStep(rawValue: raw) ?? .welcome)
  }

  public var body: some View {
    ZStack {
      AppGradientBackground()

      card
        .frame(width: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .scaleEffect(appeared ? 1 : 0.96)
        .opacity(appeared ? 1 : 0)
    }
    .task {
      refreshState()
      withAnimation(.smooth(duration: 0.45)) {
        appeared = true
      }
    }
    .onChange(of: step) { _, newValue in
      OnboardingPreferences.setStep(newValue.rawValue)
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      refreshState()
    }
  }

  private var card: some View {
    VStack(spacing: 22) {
      StepIndicator(current: step)

      ZStack {
        stepContent
          .id(step)
          .transition(stepTransition)
      }
      .frame(maxWidth: .infinity, minHeight: 300, alignment: .top)
      .clipped()

      Divider()

      footer
    }
    .padding(28)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.08))
    }
    .shadow(color: .black.opacity(0.22), radius: 28, y: 12)
  }

  @ViewBuilder
  private var stepContent: some View {
    switch step {
    case .welcome:
      WelcomeStepView()
    case .recordings:
      LocationStepView(
        title: "Where should recordings be saved?",
        explanation: "Each meeting is stored in its own folder with the audio and a Markdown transcript. You can keep the default location or choose another folder.",
        directory: recordingsDirectory,
        isDefault: recordingsDirectory.standardizedFileURL == StorageLocationPreferences.defaultRecordingsDirectory.standardizedFileURL,
        onChoose: chooseRecordingsLocation,
        onUseDefault: { applyRecordingsLocation(StorageLocationPreferences.defaultRecordingsDirectory) }
      )
    case .model:
      LocationStepView(
        title: "Where should the model be stored?",
        explanation: "The transcription model is about 1.6 GB. Some people prefer to keep it on an external drive to save space on the startup disk.",
        directory: modelDirectory,
        isDefault: modelDirectory.standardizedFileURL == StorageLocationPreferences.defaultModelDirectory.standardizedFileURL,
        onChoose: chooseModelLocation,
        onUseDefault: { applyModelLocation(StorageLocationPreferences.defaultModelDirectory) }
      )
    case .download:
      ModelDownloadStepView(manager: modelManager)
    case .permissions:
      PermissionsStepView(permissions: recorder.permissions)
    case .finish:
      FinishStepView()
    }
  }

  private var footer: some View {
    VStack(spacing: 10) {
      if let locationError {
        Text(locationError)
          .font(.callout)
          .foregroundStyle(.red)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
          .transition(.opacity)
      }

      HStack {
        Button("Back") {
          goBack()
        }
        .buttonStyle(.bordered)
        .disabled(step == .welcome)
        .pointingHandCursor(enabled: step != .welcome)

        Spacer()

        Text("Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count)")
          .font(.caption)
          .foregroundStyle(.secondary)
          .monospacedDigit()
          .contentTransition(.numericText())

        Spacer()

        Button(continueTitle) {
          goForward()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!canContinue)
        .pointingHandCursor(enabled: canContinue)
        .keyboardShortcut(.defaultAction)
      }
    }
  }

  private var continueTitle: String {
    step == .finish ? "Start using MeetingAssistant" : "Continue"
  }

  private var canContinue: Bool {
    switch step {
    case .welcome, .recordings, .model, .finish:
      return true
    case .download:
      return modelManager.isModelOnDisk()
    case .permissions:
      return recorder.permissions.bothAuthorised
    }
  }

  private func goForward() {
    guard canContinue else { return }
    if step == .finish {
      finish()
      return
    }
    guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
    goingForward = true
    withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
      step = next
    }
    refreshState()
  }

  private func goBack() {
    guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
    goingForward = false
    withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
      step = previous
    }
    refreshState()
  }

  private func finish() {
    OnboardingPreferences.setStep(0)
    onComplete()
  }

  private func refreshState() {
    modelManager.refreshStatus()
    recorder.permissions.refreshCachedStatuses()
  }

  private var stepTransition: AnyTransition {
    .asymmetric(
      insertion: .move(edge: goingForward ? .trailing : .leading).combined(with: .opacity),
      removal: .move(edge: goingForward ? .leading : .trailing).combined(with: .opacity)
    )
  }

  private func chooseRecordingsLocation() {
    guard let url = DirectoryPicker.chooseDirectory(
      message: "Choose a folder to store your meeting recordings."
    ) else { return }
    applyRecordingsLocation(url)
  }

  private func chooseModelLocation() {
    guard let url = DirectoryPicker.chooseDirectory(
      message: "Choose a folder to store the transcription model (about 1.6 GB)."
    ) else { return }
    applyModelLocation(url)
  }

  private func applyRecordingsLocation(_ url: URL) {
    StorageLocationPreferences.setRecordingsDirectory(url)
    recordingsDirectory = StorageLocationPreferences.recordingsDirectory()
    Task {
      do {
        try await store.updateRootDirectory(to: recordingsDirectory, moveExisting: true)
        locationError = nil
      } catch {
        locationError = error.localizedDescription
      }
    }
  }

  private func applyModelLocation(_ url: URL) {
    StorageLocationPreferences.setModelDirectory(url)
    modelDirectory = StorageLocationPreferences.modelDirectory()
    Task {
      do {
        try await modelManager.updateDownloadBase(to: modelDirectory, moveExisting: true)
        locationError = nil
      } catch {
        locationError = error.localizedDescription
      }
    }
  }
}

private struct StepIndicator: View {
  let current: OnboardingStep

  var body: some View {
    HStack(spacing: 8) {
      ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
        Capsule()
          .fill(step.rawValue <= current.rawValue ? Color.accentColor : Color.primary.opacity(0.18))
          .frame(width: step == current ? 26 : 8, height: 8)
      }
    }
    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: current)
  }
}

private struct OnboardingHeader: View {
  let systemImage: String
  let title: String
  let subtitle: String

  @State private var bounce = false

  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: systemImage)
        .font(.system(size: 42, weight: .regular))
        .foregroundStyle(.tint)
        .symbolEffect(.bounce, options: .nonRepeating, value: bounce)
        .onAppear {
          bounce.toggle()
        }
      Text(title)
        .font(.title.weight(.semibold))
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
      Text(subtitle)
        .font(.callout)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity)
  }
}

private struct WelcomeStepView: View {
  var body: some View {
    VStack(spacing: 22) {
      OnboardingHeader(
        systemImage: "waveform.badge.mic",
        title: "Welcome to MeetingAssistant",
        subtitle: "Record a meeting's computer audio and microphone, then transcribe it locally on this Mac."
      )

      GroupBox {
        HStack(alignment: .top, spacing: 12) {
          Image(systemName: "lock.shield")
            .font(.title3)
            .foregroundStyle(.tint)
          VStack(alignment: .leading, spacing: 6) {
            Text("Your recordings stay on this Mac")
              .font(.callout.weight(.semibold))
            Text("Recording and transcription happen entirely on-device. The only time MeetingAssistant uses the network is a one-time download of the transcription model. Nothing else is uploaded.")
              .font(.callout)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          Spacer(minLength: 0)
        }
        .padding(8)
      }

      Text("This short setup chooses where your files are stored, downloads the model, and grants the permissions recording needs.")
        .font(.callout)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

private struct LocationStepView: View {
  let title: String
  let explanation: String
  let directory: URL
  let isDefault: Bool
  let onChoose: () -> Void
  let onUseDefault: () -> Void

  var body: some View {
    VStack(spacing: 22) {
      OnboardingHeader(
        systemImage: "folder",
        title: title,
        subtitle: explanation
      )

      GroupBox {
        VStack(alignment: .leading, spacing: 12) {
          LabeledContent("Location") {
            Text(directory.path)
              .lineLimit(2)
              .truncationMode(.middle)
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
              .contentTransition(.opacity)
          }

          HStack(spacing: 10) {
            Button {
              onChoose()
            } label: {
              Label("Choose folder…", systemImage: "folder.badge.gearshape")
            }
            .pointingHandCursor()

            Button("Use default") {
              onUseDefault()
            }
            .disabled(isDefault)
            .pointingHandCursor(enabled: !isDefault)

            Spacer()
          }
        }
        .padding(8)
      }
    }
  }
}

private struct ModelDownloadStepView: View {
  let manager: ModelDownloadManager

  private static let sizeFormatter: ByteCountFormatter = {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useMB, .useGB]
    formatter.countStyle = .file
    return formatter
  }()

  var body: some View {
    VStack(spacing: 22) {
      OnboardingHeader(
        systemImage: "arrow.down.circle",
        title: "Download the transcription model",
        subtitle: "MeetingAssistant transcribes on-device with WhisperKit. The model is downloaded once, then reused. You can continue once it is ready."
      )

      GroupBox {
        VStack(alignment: .leading, spacing: 14) {
          HStack(spacing: 10) {
            Circle()
              .fill(statusColor)
              .frame(width: 9, height: 9)
              .opacity(isBusy ? 0.4 : 1)
              .scaleEffect(isBusy ? 1.35 : 1)
              .animation(isBusy ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default, value: isBusy)
            Text(manager.status.displayLabel)
            Spacer()
            if let bytes = manager.onDiskSizeBytes {
              Text(Self.sizeFormatter.string(fromByteCount: bytes))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
          }
          .font(.callout)

          switch manager.status {
          case .downloading(let fraction, _):
            ProgressView(value: fraction)
              .progressViewStyle(.linear)
          case .waitingForNetwork, .loading:
            ProgressView()
              .progressViewStyle(.linear)
          default:
            EmptyView()
          }

          actionButton
        }
        .padding(8)
      }

      if let error = manager.lastError, isFailed {
        Text(error)
          .font(.callout)
          .foregroundStyle(.red)
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .animation(.snappy, value: manager.status)
    .onAppear {
      manager.refreshStatus()
    }
  }

  @ViewBuilder
  private var actionButton: some View {
    switch manager.status {
    case .unknown, .notDownloaded, .failed:
      Button {
        manager.startDownload()
      } label: {
        Label("Download Model", systemImage: "arrow.down.circle")
      }
      .buttonStyle(.borderedProminent)
      .pointingHandCursor()
    case .downloading, .waitingForNetwork, .loading:
      Button {
        manager.cancelDownload()
      } label: {
        Label("Cancel", systemImage: "xmark.circle")
      }
      .pointingHandCursor()
    case .downloaded, .ready:
      Label("Model ready", systemImage: "checkmark.circle.fill")
        .foregroundStyle(.green)
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }
  }

  private var isBusy: Bool {
    manager.status.isBusy
  }

  private var isFailed: Bool {
    if case .failed = manager.status { return true }
    return false
  }

  private var statusColor: Color {
    switch manager.status {
    case .ready, .downloaded: return .green
    case .downloading, .loading, .waitingForNetwork: return .orange
    case .failed: return .red
    case .notDownloaded, .unknown: return .secondary
    }
  }
}

private struct PermissionsStepView: View {
  let permissions: PermissionCenter

  var body: some View {
    VStack(spacing: 22) {
      OnboardingHeader(
        systemImage: "checklist",
        title: "Grant recording permissions",
        subtitle: "Recording needs Microphone access for your voice and Screen Recording access to capture the computer audio."
      )

      GroupBox {
        VStack(spacing: 14) {
          PermissionRow(
            title: "Microphone",
            systemImage: "mic",
            state: permissions.microphone
          ) {
            MicrophonePermissionButton(permissions: permissions)
          }

          Divider()

          PermissionRow(
            title: "Screen Recording",
            systemImage: "rectangle.inset.filled.and.person.filled",
            state: permissions.systemAudio
          ) {
            ScreenRecordingPermissionButton(permissions: permissions)
          }
        }
        .padding(8)
      }

      if permissions.systemAudio != .authorized {
        Text("macOS only applies a freshly granted Screen Recording permission after the app relaunches. If it still shows as not granted after you enable it, use Quit & Reopen.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
          .transition(.opacity)
      }
    }
    .animation(.snappy, value: permissions.microphone)
    .animation(.snappy, value: permissions.systemAudio)
    .onAppear {
      permissions.refreshCachedStatuses()
    }
  }
}

private struct PermissionRow<Trailing: View>: View {
  let title: String
  let systemImage: String
  let state: PermissionState
  @ViewBuilder var trailing: () -> Trailing

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: systemImage)
        .font(.title3)
        .foregroundStyle(.tint)
        .frame(width: 24)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.callout.weight(.semibold))
        Text(stateLabel)
          .font(.caption)
          .foregroundStyle(state == .authorized ? Color.green : .secondary)
          .contentTransition(.opacity)
      }
      Spacer()
      trailing()
    }
  }

  private var stateLabel: String {
    switch state {
    case .authorized:
      return "Granted"
    case .denied:
      return "Not granted"
    case .restricted:
      return "Restricted by this Mac"
    case .unknown:
      return "Not requested yet"
    }
  }
}

private struct MicrophonePermissionButton: View {
  let permissions: PermissionCenter

  var body: some View {
    if permissions.microphone == .authorized {
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.green)
        .transition(.scale(scale: 0.5).combined(with: .opacity))
    } else if permissions.microphone == .denied || permissions.microphone == .restricted {
      Button("Open Settings") {
        permissions.openMicrophoneSettings()
      }
      .pointingHandCursor()
    } else {
      Button("Allow") {
        Task {
          await permissions.requestMicrophonePermission()
        }
      }
      .buttonStyle(.borderedProminent)
      .pointingHandCursor()
    }
  }
}

private struct ScreenRecordingPermissionButton: View {
  let permissions: PermissionCenter

  var body: some View {
    if permissions.systemAudio == .authorized {
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.green)
        .transition(.scale(scale: 0.5).combined(with: .opacity))
    } else {
      HStack(spacing: 8) {
        Button("Open Settings") {
          permissions.openScreenRecordingSettings()
        }
        .pointingHandCursor()

        Button("Quit & Reopen") {
          permissions.relaunch()
        }
        .pointingHandCursor()

        Button("Allow") {
          permissions.requestSystemAudioPermission()
        }
        .buttonStyle(.borderedProminent)
        .pointingHandCursor()
      }
    }
  }
}

private struct FinishStepView: View {
  var body: some View {
    VStack(spacing: 22) {
      OnboardingHeader(
        systemImage: "checkmark.seal.fill",
        title: "You're all set",
        subtitle: "Setup is complete. You can change any of these choices later in Settings."
      )

      Text("Give your meeting a title on the next screen and press Start Recording when you're ready.")
        .font(.callout)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}
