import Testing
@testable import MeetingAssistantCore

@Suite("TimecodeFormatter")
struct TimecodeFormatterTests {
  @Test
  func formatsHoursMinutesAndSeconds() {
    #expect(TimecodeFormatter.string(from: 0) == "00:00:00")
    #expect(TimecodeFormatter.string(from: 65.9) == "00:01:05")
    #expect(TimecodeFormatter.string(from: 3_661) == "01:01:01")
  }

  @Test
  func handlesNonFiniteInputsGracefully() {
    #expect(TimecodeFormatter.string(from: .nan) == "00:00:00")
    #expect(TimecodeFormatter.string(from: .infinity) == "00:00:00")
    #expect(TimecodeFormatter.string(from: -.infinity) == "00:00:00")
  }
}

