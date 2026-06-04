import AVFAudio
import CoreMedia
import Foundation

public extension CMSampleBuffer {
  var presentationSeconds: TimeInterval? {
    let time = CMSampleBufferGetPresentationTimeStamp(self)
    guard time.isValid && !time.seconds.isNaN else { return nil }
    return time.seconds
  }

  func makePCMBuffer() -> AVAudioPCMBuffer? {
    guard let formatDescription = CMSampleBufferGetFormatDescription(self),
          let streamDescriptionPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
    else {
      return nil
    }

    var streamDescription = streamDescriptionPointer.pointee
    guard let format = AVAudioFormat(streamDescription: &streamDescription) else {
      return nil
    }

    let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(self))
    guard frameCount > 0,
          let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
    else {
      return nil
    }

    buffer.frameLength = frameCount
    let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
      self,
      at: 0,
      frameCount: Int32(frameCount),
      into: buffer.mutableAudioBufferList
    )

    guard status == noErr else { return nil }
    return buffer
  }
}

public extension AVAudioPCMBuffer {
  /// Overwrites all samples with silence, keeping the frame length intact. Used to record a
  /// muted microphone as silence without disturbing the timeline.
  func zeroAudio() {
    let frameCount = Int(frameLength)
    let channelCount = Int(format.channelCount)
    guard frameCount > 0 else { return }

    if let floatChannelData {
      for channel in 0..<channelCount {
        floatChannelData[channel].update(repeating: 0, count: frameCount)
      }
    }
    if let int16ChannelData {
      for channel in 0..<channelCount {
        int16ChannelData[channel].update(repeating: 0, count: frameCount)
      }
    }
    if let int32ChannelData {
      for channel in 0..<channelCount {
        int32ChannelData[channel].update(repeating: 0, count: frameCount)
      }
    }
  }

  func normalizedRMSLevel() -> Float {
    guard frameLength > 0 else { return 0 }

    if let floatChannelData {
      var sum = Float.zero
      let channelCount = Int(format.channelCount)
      let frameCount = Int(frameLength)
      for channel in 0..<channelCount {
        let samples = floatChannelData[channel]
        for frame in 0..<frameCount {
          let value = samples[frame]
          sum += value * value
        }
      }
      let mean = sum / Float(max(1, channelCount * frameCount))
      return min(1, sqrt(mean) * 6)
    }

    if let int16ChannelData {
      var sum = Float.zero
      let channelCount = Int(format.channelCount)
      let frameCount = Int(frameLength)
      for channel in 0..<channelCount {
        let samples = int16ChannelData[channel]
        for frame in 0..<frameCount {
          let value = Float(samples[frame]) / Float(Int16.max)
          sum += value * value
        }
      }
      let mean = sum / Float(max(1, channelCount * frameCount))
      return min(1, sqrt(mean) * 6)
    }

    return 0
  }
}

