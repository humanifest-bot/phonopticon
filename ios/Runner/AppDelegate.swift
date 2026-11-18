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
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PhonopticonExport") else { return }
    let channel = FlutterMethodChannel(
      name: "com.humanifest.phonopticon/export",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "shareBundle",
            let arguments = call.arguments as? [String: Any],
            let json = arguments["json"] as? String,
            let filename = arguments["filename"] as? String
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      do {
        let directory = FileManager.default.temporaryDirectory
          .appendingPathComponent("phonopticon-export", isDirectory: true)
        try FileManager.default.createDirectory(
          at: directory,
          withIntermediateDirectories: true
        )
        let file = directory.appendingPathComponent(filename)
        try json.data(using: .utf8)?.write(to: file)
        guard let presenter = self?.window?.rootViewController
          ?? UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.windows.first?.rootViewController })
            .first
        else {
          result(["status": "error", "detail": "No view controller"])
          return
        }
        let activity = UIActivityViewController(
          activityItems: [file],
          applicationActivities: nil
        )
        activity.completionWithItemsHandler = { activityType, completed, _, activityError in
          if let activityError {
            result(["status": "error", "detail": activityError.localizedDescription])
          } else if completed {
            if activityType == .saveToFiles {
              result(["status": "saved", "detail": file.path])
            } else {
              result(["status": "shared", "detail": file.path])
            }
          } else {
            result(["status": "cancelled", "detail": filename])
          }
        }
        presenter.present(activity, animated: true)
      } catch {
        result(["status": "error", "detail": error.localizedDescription])
      }
    }
  }
}
