import AVFAudio
import CoreMedia
import Foundation

final class CapturedAudioFileWriter {
  let url: URL
  private var audioFile: AVAudioFile?

  init(url: URL) {
    self.url = url
  }

  func write(sampleBuffer: CMSampleBuffer) throws -> Float {
    guard let pcmBuffer = sampleBuffer.makePCMBuffer() else { return 0 }

    if audioFile == nil {
      audioFile = try AVAudioFile(forWriting: url, settings: pcmBuffer.format.settings)
    }

    try audioFile?.write(from: pcmBuffer)
    return pcmBuffer.normalizedRMSLevel()
  }

  func close() {
    audioFile = nil
  }
}

