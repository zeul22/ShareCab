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
    //
    // GMSServices throws an NSException on the first map mount if
    // `provideAPIKey` was never called, which crashes the app at launch on
    // machines where the `GOOGLE_MAPS_KEY` Xcode build setting isn't
    // configured. Register a placeholder in that case so the app boots; map
    // tiles won't render until a real key is supplied.
    let infoKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String
    if let key = infoKey,
       !key.isEmpty,
       key != "YOUR_GOOGLE_MAPS_KEY_HERE",
       !key.contains("$(") {
      GMSServices.provideAPIKey(key)
    } else {
      NSLog("[ShareCab] GOOGLE_MAPS_KEY not set — map tiles will not render. See app/README.md for setup.")
      GMSServices.provideAPIKey("MISSING_GOOGLE_MAPS_KEY")
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
