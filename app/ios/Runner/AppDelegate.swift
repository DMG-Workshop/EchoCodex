import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Not a pub plugin, so it is not in the generated registrant: the file decoder lives
    // in the app target because it is the app's own platform channel.
    if let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "AudioDecoderPlugin")
    {
      AudioDecoderPlugin.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "SharedFilePlugin")
    {
      SharedFilePlugin.register(with: registrar)
    }
  }
}
