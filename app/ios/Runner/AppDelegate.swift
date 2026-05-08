import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Register the Google Maps SDK. The key is read from Info.plist under
    // the `GMSApiKey` field so it's not hardcoded in Swift — set it once in
    // Info.plist (or override via build settings) and you're done.
    if let key = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String,
       !key.isEmpty,
       key != "YOUR_GOOGLE_MAPS_KEY_HERE" {
      GMSServices.provideAPIKey(key)
    } else {
      NSLog("[ShareCab] Google Maps key missing — set GMSApiKey in Info.plist to enable map tiles.")
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
