import Foundation
import Testing
@testable import MeetingAssistantCore

@Suite("RecordingStateMachine")
struct RecordingStateMachineTests {
  @Test
  func tracksPauseResumeAndActiveElapsed() {
    let start = Date(timeIntervalSince1970: 0)
    var machine = RecordingStateMachine()

    machine.start(at: start)
    machine.pause(at: start.addingTimeInterval(10))
    machine.resume(at: start.addingTimeInterval(25))

    #expect(machine.status == .recording)
    #expect(machine.pauses.count == 1)
    #expect(machine.wallElapsed(at: start.addingTimeInterval(40)) == 40)
    #expect(machine.activeElapsed(at: start.addingTimeInterval(40)) == 25)
  }
}

