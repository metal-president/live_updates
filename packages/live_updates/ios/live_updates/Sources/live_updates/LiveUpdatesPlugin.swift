import Flutter
import UIKit

#if canImport(live_updates_objc)
  import live_updates_objc
#endif

/// Registration entry point required by Flutter.
///
/// All functionality is exposed to Dart through FFIgen-generated Objective-C
/// bindings to `LiveUpdatesBridge`, not through platform channels. The plugin
/// only listens for tap URLs opened from a Live Activity.
public class LiveUpdatesPlugin: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate {
  /// Flutter keeps lifecycle delegates weakly, so the plugin keeps itself alive.
  private static var instances: [LiveUpdatesPlugin] = []

  public static func register(with registrar: FlutterPluginRegistrar) {
    // Keeps the FFIgen block trampolines linked into the app.
    live_updates_objc_link()
    let instance = LiveUpdatesPlugin()
    instances.append(instance)
    // Scene-based apps get URLs through the scene delegate only; registering
    // both would deliver every tap twice.
    if Bundle.main.object(forInfoDictionaryKey: "UIApplicationSceneManifest") == nil {
      registrar.addApplicationDelegate(instance)
    } else {
      registrar.addSceneDelegate(instance)
    }
  }

  public func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [AnyHashable: Any] = [:]
  ) -> Bool {
    if let url = launchOptions[UIApplication.LaunchOptionsKey.url] as? URL {
      _ = LiveUpdatesBridge.handleURL(url)
    }
    return true
  }

  public func application(
    _ app: UIApplication, open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    LiveUpdatesBridge.handleURL(url)
  }

  public func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions?
  ) -> Bool {
    connectionOptions?.urlContexts.contains { LiveUpdatesBridge.handleURL($0.url) } ?? false
  }

  public func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
    URLContexts.contains { LiveUpdatesBridge.handleURL($0.url) }
  }
}
