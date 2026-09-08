import Flutter
import UIKit

/// Receives a recording opened into the app from somewhere else — Files, Drive, a
/// conferencing app's export — and hands its path to Dart.
///
/// The incoming URL points into another app's container and the read grant is scoped to
/// this callback, so the bytes are copied into our own cache immediately: a path kept from
/// it would read as missing by the time the import actually runs.
final class SharedFilePlugin: NSObject, FlutterSceneLifeCycleDelegate {
  static let channelName = "kallanotes/shared_file"

  private var channel: FlutterMethodChannel?

  /// A file opened before Dart was ready to hear about it.
  ///
  /// A cold launch delivers the URL while the widget tree is still being built, so it is
  /// held until the first `takeSharedFile` asks for it.
  private var pending: String?

  /// Whether Dart has asked for a pending share yet.
  ///
  /// The first ask is what proves the Flutter side is up and listening, which decides how
  /// a share is delivered: held for collection before that, pushed after. A share that was
  /// both held *and* pushed would be imported twice — a duplicate note, and the
  /// transcription billed twice.
  private var dartIsListening = false

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = SharedFilePlugin()
    let channel = FlutterMethodChannel(
      name: channelName, binaryMessenger: registrar.messenger())
    instance.channel = channel

    channel.setMethodCallHandler { call, result in
      guard call.method == "takeSharedFile" else {
        result(FlutterMethodNotImplemented)
        return
      }
      // Read-and-clear: importing the same file on every resume would be worse than
      // missing one.
      instance.dartIsListening = true
      result(instance.pending)
      instance.pending = nil
    }

    registrar.addSceneDelegate(instance)
  }

  // MARK: - FlutterSceneLifeCycleDelegate

  /// A cold launch: the app was not running when the user chose it.
  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions?
  ) -> Bool {
    guard let contexts = connectionOptions?.urlContexts else { return false }
    return handle(urls: contexts.map { $0.url })
  }

  /// A file opened while the app is already running.
  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
    handle(urls: URLContexts.map { $0.url })
  }

  // MARK: - Copying

  private func handle(urls: [URL]) -> Bool {
    for url in urls where url.isFileURL {
      guard let path = copyToCache(url) else { continue }
      if dartIsListening {
        channel?.invokeMethod("onSharedFile", arguments: path)
      } else {
        pending = path
      }
      return true
    }
    return false
  }

  private func copyToCache(_ url: URL) -> String? {
    // A URL handed over by another app is security-scoped; without this the read fails.
    // Not every URL is scoped, so a false return is not itself an error.
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }

    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("shared", isDirectory: true)
    try? FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true)

    // The extension is what the Dart side matches the format on, so it is preserved
    // exactly; an extensionless file is refused there by name rather than half-imported.
    let stamp = Int(Date().timeIntervalSince1970 * 1000)
    let target = directory.appendingPathComponent(
      "\(stamp)_\(url.deletingPathExtension().lastPathComponent)"
    ).appendingPathExtension(url.pathExtension)

    do {
      if FileManager.default.fileExists(atPath: target.path) {
        try FileManager.default.removeItem(at: target)
      }
      try FileManager.default.copyItem(at: url, to: target)
    } catch {
      // A file that cannot be read is not worth failing the launch over; the user still
      // has a working app and can import through the picker.
      return nil
    }

    let size = (try? FileManager.default.attributesOfItem(atPath: target.path)[.size]) as? Int
    return (size ?? 0) > 0 ? target.path : nil
  }
}
