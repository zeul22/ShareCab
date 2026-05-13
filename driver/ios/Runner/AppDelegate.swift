import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let key = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String,
       !key.isEmpty,
       key != "YOUR_GOOGLE_MAPS_KEY_HERE",
       !key.contains("$(") {
      GMSServices.provideAPIKey(key)
    } else {
      NSLog("[ShareCab Driver] Google Maps key missing — set GMSApiKey in Info.plist to enable map tiles.")
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
