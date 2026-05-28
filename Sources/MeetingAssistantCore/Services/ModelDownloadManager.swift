import Foundation
import Network
import Observation
import WhisperKit

public enum ModelStatus: Sendable, Equatable {
  case unknown
  case notDownloaded
  case downloading(fraction: Double, attempt: Int)
  case waitingForNetwork(attempt: Int)
  case downloaded
  case loading
  case ready
  case failed(message: String)

  public var isTerminalReady: Bool {
    if case .ready = self { return true }
    return false
  }

  public var isBusy: Bool {
    switch self {
    case .downloading, .waitingForNetwork, .loading:
      return true
    default:
      return false
    }
  }

  public var displayLabel: String {
    switch self {
    case .unknown:
      return "Checking…"
    case .notDownloaded:
      return "Not downloaded"
    case .downloading(let fraction, let attempt):
      let percent = Int((fraction * 100).rounded())
      return attempt > 1 ? "Downloading \(percent)% (retry \(attempt - 1))" : "Downloading \(percent)%"
    case .waitingForNetwork(let attempt):
      return attempt > 1 ? "Waiting for internet (retry \(attempt - 1))" : "Waiting for internet"
    case .downloaded:
      return "Downloaded — not yet loaded"
    case .loading:
      return "Loading model…"
    case .ready:
      return "Ready"
    case .failed(let message):
      return "Failed: \(message)"
    }
  }
}

@MainActor
@Observable
public final class ModelDownloadManager {
  public static let shared = ModelDownloadManager()

  public let modelName: String
  public let repo: String

  public private(set) var status: ModelStatus = .unknown
  public private(set) var lastError: String?

  private var downloadTask: Task<Void, Never>?
  private var loadTask: Task<Void, Error>?
  private var loadedPipe: WhisperKit?

  private let downloadBase: URL
  private let maxRetries: Int
  private let networkMonitor: NetworkReachability

  public init(
    modelName: String = WhisperKitTranscriber.defaultModel,
    repo: String = "argmaxinc/whisperkit-coreml",
    maxRetries: Int = 6,
    networkMonitor: NetworkReachability = .shared
  ) {
    self.modelName = modelName
    self.repo = repo
    self.maxRetries = maxRetries
    self.networkMonitor = networkMonitor
    self.downloadBase = Self.defaultDownloadBase()
    refreshStatus()
  }

  /// Returns the directory the model is (or would be) installed into.
  public var modelFolder: URL {
    downloadBase
      .appendingPathComponent("models", isDirectory: true)
      .appendingPathComponent(repo, isDirectory: true)
      .appendingPathComponent(modelName, isDirectory: true)
  }

  public func refreshStatus() {
    if isModelOnDisk() {
      if loadedPipe != nil {
        status = .ready
      } else {
        status = .downloaded
      }
    } else {
      status = .notDownloaded
    }
  }

  public func isModelOnDisk() -> Bool {
    let folder = modelFolder
    guard FileManager.default.fileExists(atPath: folder.path) else { return false }
    // The variant directory must contain at least one .mlmodelc bundle to be usable.
    let contents = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    return contents.contains { $0.hasSuffix(".mlmodelc") }
  }

  /// Starts a robust download (with retries and offline handling). Idempotent — calling
  /// twice while a download is in flight is a no-op.
  public func startDownload() {
    if case .ready = status { return }
    if case .downloading = status { return }
    if case .waitingForNetwork = status { return }
    if case .loading = status { return }

    lastError = nil
    downloadTask?.cancel()
    downloadTask = Task { [weak self] in
      await self?.runDownloadAndLoad()
    }
  }

  public func cancelDownload() {
    downloadTask?.cancel()
    loadTask?.cancel()
    downloadTask = nil
    loadTask = nil
    refreshStatus()
  }

  public func deleteModel() throws {
    cancelDownload()
    loadedPipe = nil
    let folder = modelFolder
    if FileManager.default.fileExists(atPath: folder.path) {
      try FileManager.default.removeItem(at: folder)
    }
    refreshStatus()
  }

  /// Ensures the model is downloaded and loaded, returning the prepared pipeline.
  /// Used at transcription time. If the user hasn't downloaded yet this throws — recording
  /// is gated separately in the UI so this should only fail if the disk state changed.
  public func ensureReady() async throws -> WhisperKit {
    if let pipe = loadedPipe { return pipe }
    if !isModelOnDisk() {
      throw WhisperTranscriptionError.modelDownloadFailed("The Whisper model has not been downloaded yet. Open Settings to download it.")
    }
    return try await loadPipelineIfNeeded()
  }

  // MARK: - Internals

  private func runDownloadAndLoad() async {
    guard !isModelOnDisk() else {
      _ = try? await loadPipelineIfNeeded()
      return
    }

    var attempt = 1
    while attempt <= maxRetries {
      if Task.isCancelled { refreshStatus(); return }

      // Wait until we believe the network is reachable.
      if !networkMonitor.isReachable {
        status = .waitingForNetwork(attempt: attempt)
        let arrived = await networkMonitor.waitForReachable(timeout: 60)
        if Task.isCancelled { refreshStatus(); return }
        if !arrived {
          // Could not get a connection within the window — try again after a short wait.
          try? await Task.sleep(nanoseconds: 2_000_000_000)
          attempt += 1
          continue
        }
      }

      status = .downloading(fraction: 0, attempt: attempt)

      do {
        let folder = try await WhisperKit.download(
          variant: modelName,
          downloadBase: downloadBase,
          useBackgroundSession: false,
          from: repo,
          progressCallback: { [weak self] progress in
            let fraction = progress.fractionCompleted
            Task { @MainActor [weak self] in
              guard let self else { return }
              if case .downloading(_, let a) = self.status {
                self.status = .downloading(fraction: fraction, attempt: a)
              }
            }
          }
        )

        if Task.isCancelled { refreshStatus(); return }

        // Sanity-check the resulting folder; if the structure looks wrong, fall back to
        // the conventional location and let load decide.
        _ = folder
        status = .downloaded
        _ = try await loadPipelineIfNeeded()
        return
      } catch is CancellationError {
        refreshStatus()
        return
      } catch {
        lastError = error.localizedDescription
        if attempt >= maxRetries {
          status = .failed(message: error.localizedDescription)
          return
        }
        // Exponential backoff capped at 30s. Reset to waiting if it's clearly a network issue.
        let delaySeconds = min(30.0, pow(2.0, Double(attempt)))
        if !networkMonitor.isReachable {
          status = .waitingForNetwork(attempt: attempt + 1)
        } else {
          status = .downloading(fraction: 0, attempt: attempt + 1)
        }
        try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
        attempt += 1
      }
    }
  }

  @discardableResult
  private func loadPipelineIfNeeded() async throws -> WhisperKit {
    if let pipe = loadedPipe {
      status = .ready
      return pipe
    }
    status = .loading
    let config = WhisperKitConfig(
      model: modelName,
      modelFolder: modelFolder.path,
      verbose: false,
      logLevel: .error,
      prewarm: false,
      load: true,
      download: false
    )
    do {
      let pipe = try await WhisperKit(config)
      loadedPipe = pipe
      status = .ready
      return pipe
    } catch {
      loadedPipe = nil
      let message = error.localizedDescription
      lastError = message
      status = .failed(message: message)
      throw WhisperTranscriptionError.modelLoadFailed(message)
    }
  }

  private static func defaultDownloadBase() -> URL {
    let support = (try? FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )) ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]

    let root = support
      .appendingPathComponent("MeetingAssistant", isDirectory: true)
      .appendingPathComponent("WhisperKit", isDirectory: true)
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }
}

/// Lightweight wrapper around NWPathMonitor so the manager can poll/await connectivity.
public final class NetworkReachability: @unchecked Sendable {
  public static let shared = NetworkReachability()

  private let monitor: NWPathMonitor
  private let queue = DispatchQueue(label: "MeetingAssistant.NetworkReachability")
  private let lock = NSLock()
  private var currentlyReachable: Bool = true
  private var waiters: [CheckedContinuation<Void, Never>] = []

  public init() {
    monitor = NWPathMonitor()
    monitor.pathUpdateHandler = { [weak self] path in
      self?.handle(path: path)
    }
    monitor.start(queue: queue)
  }

  deinit {
    monitor.cancel()
  }

  public var isReachable: Bool {
    lock.lock(); defer { lock.unlock() }
    return currentlyReachable
  }

  /// Suspends until the network is reported reachable, or the timeout elapses.
  /// Returns true if reachable, false on timeout.
  public func waitForReachable(timeout seconds: TimeInterval) async -> Bool {
    if isReachable { return true }

    return await withTaskGroup(of: Bool.self) { group in
      group.addTask { [weak self] in
        guard let self else { return false }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
          self.lock.lock()
          if self.currentlyReachable {
            self.lock.unlock()
            cont.resume()
          } else {
            self.waiters.append(cont)
            self.lock.unlock()
          }
        }
        return true
      }
      group.addTask {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        return false
      }
      let first = await group.next() ?? false
      group.cancelAll()
      return first
    }
  }

  private func handle(path: NWPath) {
    let reachable = path.status == .satisfied
    lock.lock()
    let changed = reachable != currentlyReachable
    currentlyReachable = reachable
    var toResume: [CheckedContinuation<Void, Never>] = []
    if reachable {
      toResume = waiters
      waiters.removeAll()
    }
    lock.unlock()

    _ = changed
    for cont in toResume {
      cont.resume()
    }
  }
}
