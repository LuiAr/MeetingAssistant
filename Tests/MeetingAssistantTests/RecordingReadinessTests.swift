import Foundation
import Testing
@testable import MeetingAssistantCore

@Suite("RecordingReadiness")
struct RecordingReadinessTests {
  @Test
  func canRecordOnlyWhenEverythingIsReady() {
    let ready = RecordingReadiness(modelReady: true, microphoneAuthorised: true, screenRecordingAuthorised: true)
    #expect(ready.canRecord)
    #expect(ready.missingRequirements.isEmpty)
    #expect(ready.startButtonHelp == nil)
  }

  @Test
  func reportsASingleMissingRequirement() {
    let readiness = RecordingReadiness(modelReady: false, microphoneAuthorised: true, screenRecordingAuthorised: true)
    #expect(readiness.canRecord == false)
    #expect(readiness.missingRequirements == ["the transcription model"])

    let help = readiness.startButtonHelp
    #expect(help != nil)
    #expect(help?.contains("the transcription model") == true)
    #expect(help?.contains("is still needed") == true)
  }

  @Test
  func listsMissingRequirementsInOnboardingOrder() {
    let readiness = RecordingReadiness(modelReady: false, microphoneAuthorised: false, screenRecordingAuthorised: false)
    #expect(readiness.missingRequirements == [
      "the transcription model",
      "Microphone access",
      "Screen Recording access"
    ])
    #expect(readiness.startButtonHelp?.contains("are still needed") == true)
  }

  @Test
  func joinsRequirementsIntoNaturalLanguage() {
    #expect(RecordingReadiness.sentence(from: []) == "")
    #expect(RecordingReadiness.sentence(from: ["A"]) == "A")
    #expect(RecordingReadiness.sentence(from: ["A", "B"]) == "A and B")
    #expect(RecordingReadiness.sentence(from: ["A", "B", "C"]) == "A, B and C")
  }
}
