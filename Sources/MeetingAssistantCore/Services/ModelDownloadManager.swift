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
      return "Downloaded"
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

  // The active variant is fixed at construction for now. When a user-facing picker is added,
  // replace these `let`s with `var`s and add a `switchVariant(to:)` that tears down `loadedPipe`,
  // updates `modelName` / `repo`, and re-enters `refreshStatus()`. The download/load path
  // already keys off these fields, so no other call sites should need to change.
  public let modelName: String
  public let repo: String

  /// The catalog entry corresponding to `modelName`, when one is registered.
  public var activeVariant: WhisperModelVariant? {
    WhisperModelCatalog.variant(withID: modelName)
  }

  public private(set) var status: ModelStatus = .unknown
  public private(set) var lastError: String?
  /// Total bytes used by the on-disk model folder, or nil when not downloaded.
  public private(set) var onDiskSizeBytes: Int64?

  private var downloadTask: Task<Void, Never>?
  private var loadTask: Task<Void, Error>?
  private var loadedPipe: WhisperKit?

  /// The base directory the model is downloaded into. User-configurable, so it is a `var` that
  /// can be re-pointed at runtime via `updateDownloadBase(to:moveExisting:)`.
  public private(set) var downloadBase: URL
  private let maxRetries: Int
  private let networkMonitor: NetworkReachability

  public init(
    modelName: String = WhisperKitTranscriber.defaultModel,
    repo: String = "argmaxinc/whisperkit-coreml",
    maxRetries: Int = 6,
    networkMonitor: NetworkReachability = .shared,
    downloadBase: URL = StorageLocationPreferences.modelDirectory()
  ) {
    self.modelName = modelName
    self.repo = repo
    self.maxRetries = maxRetries
    self.networkMonitor = networkMonitor
    self.downloadBase = downloadBase
    refreshStatus()
  }

  /// Returns the directory the model is (or would be) installed into.
  public var modelFolder: URL {
    Self.modelFolder(base: downloadBase, repo: repo, modelName: modelName)
  }

  nonisolated private static func modelFolder(base: URL, repo: String, modelName: String) -> URL {
    base
      .appendingPathComponent("models", isDirectory: true)
      .appendingPathComponent(repo, isDirectory: true)
      .appendingPathComponent(modelName, isDirectory: true)
  }

  /// True when the model's base directory (or its containing folder) is reachable on disk. A
  /// custom base on an external drive becomes unreachable when the drive is unplugged.
  public var isDownloadBaseReachable: Bool {
    if FileManager.default.fileExists(atPath: downloadBase.path) { return true }
    let parent = downloadBase.deletingLastPathComponent()
    return FileManager.default.fileExists(atPath: parent.path)
  }

  /// Re-points the model storage location. When `moveExisting` is true and a model is present at
  /// the old location, its folder is moved to the new base; otherwise the new location is used
  /// as-is (the user can re-download into it). Tearing down `loadedPipe` forces a reload from the
  /// new path on next use.
  public func updateDownloadBase(to newBase: URL, moveExisting: Bool) async throws {
    let oldBase = downloadBase
    guard oldBase.standardizedFileURL != newBase.standardizedFileURL else { return }

    cancelDownload()
    loadedPipe = nil

    if moveExisting {
      let repo = self.repo
      let modelName = self.modelName
      // Moving the model (about 1.6 GB) can be a cross-volume copy to an external drive, so it
      // runs off the main actor to avoid hitching the UI.
      try await Task.detached(priority: .userInitiated) {
        let oldFolder = Self.modelFolder(base: oldBase, repo: repo, modelName: modelName)
        guard FileManager.default.fileExists(atPath: oldFolder.path) else { return }
        let newFolder = Self.modelFolder(base: newBase, repo: repo, modelName: modelName)
        try FileManager.default.createDirectory(
          at: newFolder.deletingLastPathComponent(),
          withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: newFolder.path) {
          try FileManager.default.removeItem(at: newFolder)
        }
        try FileManager.default.moveItem(at: oldFolder, to: newFolder)
      }.value
    }

    downloadBase = newBase
    refreshStatus()
  }

  public func refreshStatus() {
    if isModelOnDisk() {
      if loadedPipe != nil {
        status = .ready
      } else {
        status = .downloaded
      }
      refreshOnDiskSize()
    } else {
      status = .notDownloaded
      onDiskSizeBytes = nil
    }
  }

  /// Computes the on-disk size off the main actor and publishes it back, so walking a
  /// multi-gigabyte model folder never blocks the UI.
  private func refreshOnDiskSize() {
    let folder = modelFolder
    Task { [weak self] in
      let size = await Task.detached(priority: .utility) {
        Self.computeOnDiskSize(at: folder)
      }.value
      self?.onDiskSizeBytes = size
    }
  }

  /// Walks `folder` and returns its total byte size, or nil if it doesn't exist.
  nonisolated private static func computeOnDiskSize(at folder: URL) -> Int64? {
    let fm = FileManager.default
    guard fm.fileExists(atPath: folder.path) else { return nil }
    guard let enumerator = fm.enumerator(
      at: folder,
      includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey],
      options: [.skipsHiddenFiles]
    ) else { return nil }

    var total: Int64 = 0
    for case let url as URL in enumerator {
      let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey])
      guard values?.isRegularFile == true else { continue }
      if let allocated = values?.totalFileAllocatedSize {
        total += Int64(allocated)
      } else if let size = values?.fileSize {
        total += Int64(size)
      }
    }
    return total
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

    // Ensure the (possibly custom) base directory exists before WhisperKit downloads into it.
    try? FileManager.default.createDirectory(at: downloadBase, withIntermediateDirectories: true)

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
        refreshOnDiskSize()
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
}

/// Lightweight wrapper around NWPathMonitor so the manager can poll/await connectivity.
public final class NetworkReachability: @unchecked Sendable {
  public static let shared = NetworkReachability()

  private let monitor: NWPathMonitor
  private let queue = DispatchQueue(label: "MeetingAssistant.NetworkReachability")
  private let lock = NSLock()
  private var currentlyReachable: Bool = true
  private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]

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
        await self.waitForReachableSignal()
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

  /// Suspends until `handle(path:)` reports the network reachable. Cancellation-aware: if the
  /// surrounding task is cancelled (for example when the timeout branch wins), the stored
  /// continuation is removed and resumed so it never leaks. The `lock` serialises the
  /// install and the cancel/resume so the continuation is always resumed exactly once.
  private func waitForReachableSignal() async {
    let id = UUID()
    await withTaskCancellationHandler {
      await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
        lock.lock()
        if currentlyReachable || Task.isCancelled {
          lock.unlock()
          cont.resume()
          return
        }
        waiters[id] = cont
        lock.unlock()
      }
    } onCancel: {
      lock.lock()
      let cont = waiters.removeValue(forKey: id)
      lock.unlock()
      cont?.resume()
    }
  }

  private func handle(path: NWPath) {
    let reachable = path.status == .satisfied
    lock.lock()
    currentlyReachable = reachable
    var toResume: [CheckedContinuation<Void, Never>] = []
    if reachable {
      toResume = Array(waiters.values)
      waiters.removeAll()
    }
    lock.unlock()

    for cont in toResume {
      cont.resume()
    }
  }
}
