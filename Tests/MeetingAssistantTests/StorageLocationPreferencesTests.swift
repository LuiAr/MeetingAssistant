import Foundation
import Testing
@testable import MeetingAssistantCore

@Suite("StorageLocationPreferences")
struct StorageLocationPreferencesTests {
  private func makeDefaults() -> (UserDefaults, () -> Void) {
    let suite = "MeetingAssistantTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    return (defaults, { defaults.removePersistentDomain(forName: suite) })
  }

  @Test
  func resolveDirectoryFallsBackToDefaultForMissingOrEmptyPaths() {
    let fallback = URL(fileURLWithPath: "/tmp/Default", isDirectory: true)

    #expect(StorageLocationPreferences.resolveDirectory(storedPath: nil, default: fallback).path == fallback.path)
    #expect(StorageLocationPreferences.resolveDirectory(storedPath: "", default: fallback).path == fallback.path)
    #expect(StorageLocationPreferences.resolveDirectory(storedPath: "   ", default: fallback).path == fallback.path)
  }

  @Test
  func resolveDirectoryUsesStoredPathWhenPresent() {
    let fallback = URL(fileURLWithPath: "/tmp/Default", isDirectory: true)
    let resolved = StorageLocationPreferences.resolveDirectory(storedPath: "/Volumes/External/Recordings", default: fallback)

    #expect(resolved.path == "/Volumes/External/Recordings")
  }

  @Test
  func defaultsHaveExpectedLeafFolders() {
    #expect(StorageLocationPreferences.defaultRecordingsDirectory.lastPathComponent == "MeetingAssistant Recordings")
    #expect(StorageLocationPreferences.defaultModelDirectory.lastPathComponent == "WhisperKit")
  }

  @Test
  func freshDefaultsResolveToTheDefaultDirectories() {
    let (defaults, cleanup) = makeDefaults()
    defer { cleanup() }

    #expect(
      StorageLocationPreferences.recordingsDirectory(defaults: defaults).standardizedFileURL
        == StorageLocationPreferences.defaultRecordingsDirectory.standardizedFileURL
    )
    #expect(
      StorageLocationPreferences.modelDirectory(defaults: defaults).standardizedFileURL
        == StorageLocationPreferences.defaultModelDirectory.standardizedFileURL
    )
    #expect(StorageLocationPreferences.isUsingCustomRecordingsDirectory(defaults: defaults) == false)
    #expect(StorageLocationPreferences.isUsingCustomModelDirectory(defaults: defaults) == false)
  }

  @Test
  func settingAndClearingACustomRecordingsDirectory() {
    let (defaults, cleanup) = makeDefaults()
    defer { cleanup() }

    let custom = FileManager.default.temporaryDirectory.appendingPathComponent("Custom-\(UUID().uuidString)", isDirectory: true)
    StorageLocationPreferences.setRecordingsDirectory(custom, defaults: defaults)

    #expect(
      StorageLocationPreferences.recordingsDirectory(defaults: defaults).standardizedFileURL == custom.standardizedFileURL
    )
    #expect(StorageLocationPreferences.isUsingCustomRecordingsDirectory(defaults: defaults) == true)

    // Storing the default clears the override.
    StorageLocationPreferences.setRecordingsDirectory(StorageLocationPreferences.defaultRecordingsDirectory, defaults: defaults)
    #expect(defaults.string(forKey: StorageLocationPreferences.recordingsDirectoryKey) == nil)
    #expect(StorageLocationPreferences.isUsingCustomRecordingsDirectory(defaults: defaults) == false)

    // Setting then clearing with nil also removes the override.
    StorageLocationPreferences.setRecordingsDirectory(custom, defaults: defaults)
    StorageLocationPreferences.setRecordingsDirectory(nil, defaults: defaults)
    #expect(defaults.string(forKey: StorageLocationPreferences.recordingsDirectoryKey) == nil)
  }

  @Test
  func settingACustomModelDirectory() {
    let (defaults, cleanup) = makeDefaults()
    defer { cleanup() }

    let custom = FileManager.default.temporaryDirectory.appendingPathComponent("Model-\(UUID().uuidString)", isDirectory: true)
    StorageLocationPreferences.setModelDirectory(custom, defaults: defaults)

    #expect(
      StorageLocationPreferences.modelDirectory(defaults: defaults).standardizedFileURL == custom.standardizedFileURL
    )
    #expect(StorageLocationPreferences.isUsingCustomModelDirectory(defaults: defaults) == true)
  }

  @Test
  func onboardingCompletionRoundTripsAndResets() {
    let (defaults, cleanup) = makeDefaults()
    defer { cleanup() }

    #expect(OnboardingPreferences.isComplete(defaults: defaults) == false)

    OnboardingPreferences.setComplete(true, defaults: defaults)
    #expect(OnboardingPreferences.isComplete(defaults: defaults) == true)

    defaults.set(3, forKey: OnboardingPreferences.stepKey)
    OnboardingPreferences.reset(defaults: defaults)
    #expect(OnboardingPreferences.isComplete(defaults: defaults) == false)
    #expect(defaults.integer(forKey: OnboardingPreferences.stepKey) == 0)
  }
}
