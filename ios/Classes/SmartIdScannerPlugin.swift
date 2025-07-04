import Flutter
import UIKit

public class SmartIdScannerPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "smart_id_scanner", binaryMessenger: registrar.messenger())
    let instance = SmartIdScannerPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    // We don't need any platform-specific methods for this plugin
    // All functionality is handled by Flutter packages
    result(FlutterMethodNotImplemented)
  }
}