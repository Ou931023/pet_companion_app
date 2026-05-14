import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let registrar = self.registrar(forPlugin: "NativeHomeBarPlugin") {
      registrar.register(
        NativeHomeBarFactory(messenger: registrar.messenger()),
        withId: "native_home_bar"
      )
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
