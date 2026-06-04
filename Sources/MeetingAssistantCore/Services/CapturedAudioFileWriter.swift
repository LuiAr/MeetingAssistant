import AVFAudio
import CoreMedia
import Foundation

final class CapturedAudioFileWriter {
  let url: URL
  private var audioFile: AVAudioFile?

  init(url: URL) {
    self.url = url
  }

  /// Writes one sample buffer. When `muted`, the PCM data is zeroed before writing so the
  /// file keeps the same duration/timeline (silence instead of audio), which keeps the
  /// microphone track aligned with the system track for transcription.
  func write(sampleBuffer: CMSampleBuffer, muted: Bool = false) throws -> Float {
    guard let pcmBuffer = sampleBuffer.makePCMBuffer() else { return 0 }

    if muted {
      pcmBuffer.zeroAudio()
    }

    if audioFile == nil {
      audioFile = try AVAudioFile(forWriting: url, settings: pcmBuffer.format.settings)
    }

    try audioFile?.write(from: pcmBuffer)
    return muted ? 0 : pcmBuffer.normalizedRMSLevel()
  }

  func close() {
    audioFile = nil
  }
}

