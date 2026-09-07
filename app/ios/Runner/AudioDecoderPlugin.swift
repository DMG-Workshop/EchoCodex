import AVFoundation
import Flutter

/// Decodes any container iOS can open into the 16 kHz mono PCM16 WAV the transcription
/// pipeline expects.
///
/// `AVAssetReader` handles MP3, AAC, ALAC, FLAC and the MP4 family — the same codecs the
/// system uses everywhere else — so nothing has to be bundled to read a meeting exported
/// from Zoom or a voice memo from another app.
final class AudioDecoderPlugin: NSObject {
  static let channelName = "kallanotes/audio_decoder"

  private static let targetSampleRate = 16000.0
  private static let targetChannels: UInt32 = 1

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName, binaryMessenger: registrar.messenger())
    let instance = AudioDecoderPlugin()
    channel.setMethodCallHandler(instance.handle)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "decodeToWav" else {
      result(FlutterMethodNotImplemented)
      return
    }

    guard let arguments = call.arguments as? [String: Any],
      let sourcePath = arguments["sourcePath"] as? String,
      let targetPath = arguments["targetPath"] as? String
    else {
      result(
        FlutterError(
          code: "bad_arguments", message: "sourcePath and targetPath are required",
          details: nil))
      return
    }

    // An hour of audio takes long enough to decode that doing it on the main thread drops
    // frames; the result is handed back on it, which is where Flutter needs it.
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        try self.decodeToWav(sourcePath: sourcePath, targetPath: targetPath)
        DispatchQueue.main.async { result(nil) }
      } catch let error as DecodeError {
        DispatchQueue.main.async {
          result(FlutterError(code: error.code, message: error.message, details: nil))
        }
      } catch {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "decode_failed", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  private struct DecodeError: Error {
    let code: String
    let message: String
  }

  private func decodeToWav(sourcePath: String, targetPath: String) throws {
    let asset = AVURLAsset(url: URL(fileURLWithPath: sourcePath))

    guard let track = asset.tracks(withMediaType: .audio).first else {
      throw DecodeError(code: "no_audio_track", message: "The file contains no audio track.")
    }

    let reader = try AVAssetReader(asset: asset)
    // Asking the reader itself for 16 kHz mono PCM16 means the system's own converter does
    // the downmix and resample, rather than a hand-rolled one here.
    let output = AVAssetReaderTrackOutput(
      track: track,
      outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: Self.targetSampleRate,
        AVNumberOfChannelsKey: Self.targetChannels,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
      ])

    guard reader.canAdd(output) else {
      throw DecodeError(
        code: "unsupported", message: "This device has no decoder for that file.")
    }
    reader.add(output)

    let target = URL(fileURLWithPath: targetPath)
    FileManager.default.createFile(atPath: targetPath, contents: nil)
    guard let handle = try? FileHandle(forWritingTo: target) else {
      throw DecodeError(code: "write_failed", message: "The decoded file could not be written.")
    }
    defer { try? handle.close() }

    // Placeholder header, rewritten once the sample count is known.
    handle.write(Data(count: 44))

    guard reader.startReading() else {
      throw DecodeError(
        code: "decode_failed",
        message: reader.error?.localizedDescription ?? "The file could not be read.")
    }

    var bytesWritten = 0
    while let buffer = output.copyNextSampleBuffer() {
      guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }

      var length = 0
      var pointer: UnsafeMutablePointer<Int8>?
      guard
        CMBlockBufferGetDataPointer(
          block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length,
          dataPointerOut: &pointer) == kCMBlockBufferNoErr,
        let bytes = pointer, length > 0
      else { continue }

      handle.write(Data(bytes: bytes, count: length))
      bytesWritten += length
    }

    if reader.status == .failed {
      throw DecodeError(
        code: "decode_failed",
        message: reader.error?.localizedDescription ?? "Decoding stopped part-way.")
    }
    guard bytesWritten > 0 else {
      throw DecodeError(code: "no_audio", message: "The file decoded to no audio.")
    }

    try handle.seek(toOffset: 0)
    handle.write(Self.wavHeader(dataLength: bytesWritten))
  }

  /// The canonical 44-byte RIFF/WAVE header for 16 kHz mono PCM16.
  private static func wavHeader(dataLength: Int) -> Data {
    let bytesPerFrame = UInt16(targetChannels * 2)
    let sampleRate = UInt32(targetSampleRate)
    var data = Data()

    func append<T: FixedWidthInteger>(_ value: T) {
      var little = value.littleEndian
      withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }

    data.append(contentsOf: Array("RIFF".utf8))
    append(UInt32(36 + dataLength))
    data.append(contentsOf: Array("WAVE".utf8))
    data.append(contentsOf: Array("fmt ".utf8))
    append(UInt32(16))
    append(UInt16(1))  // PCM
    append(UInt16(targetChannels))
    append(sampleRate)
    append(sampleRate * UInt32(bytesPerFrame))
    append(bytesPerFrame)
    append(UInt16(16))
    data.append(contentsOf: Array("data".utf8))
    append(UInt32(dataLength))

    return data
  }
}
