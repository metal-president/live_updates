import Flutter
import Foundation

/// Runs the Dart background action handler in a headless engine when a Live
/// Activity button is pressed while no Dart listener is attached (for
/// example when the system launched the app in the background for the
/// press). Looked up by name from `LiveUpdatesBridge`, which does not link
/// Flutter.
@objc(LiveUpdatesBackgroundRunner)
public final class LiveUpdatesBackgroundRunner: NSObject {
  /// Posted when the handler finished (or timed out).
  static let doneNotification = Notification.Name("LiveUpdatesBackgroundDone")
  /// LiveActivityIntent runs get limited background time; stay well below.
  private static let timeout: TimeInterval = 25

  private static var engine: FlutterEngine?
  private static var timeoutWork: DispatchWorkItem?
  static var registrant: ((FlutterPluginRegistry) -> Void)?
  /// True while plugins register on the headless engine.
  static var registeringPlugins = false

  /// Starts the engine (once). Returns whether a handler run is in progress.
  @objc(startWithDispatcher:)
  public static func start(dispatcher: NSNumber) -> NSNumber {
    dispatchPrecondition(condition: .onQueue(.main))
    if engine != nil { return true }
    guard
      let info = FlutterCallbackCache.lookupCallbackInformation(dispatcher.int64Value)
    else { return false }
    let engine = FlutterEngine(
      name: "live_updates_background", project: nil, allowHeadlessExecution: true)
    guard engine.run(withEntrypoint: info.callbackName, libraryURI: info.callbackLibraryPath)
    else { return false }
    registeringPlugins = true
    registrant?(engine)
    registeringPlugins = false
    self.engine = engine
    let work = DispatchWorkItem { stop(mayRestart: false) }
    timeoutWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
    return true
  }

  /// Called from Dart when the handler finished.
  @objc public static func finish() {
    DispatchQueue.main.async { stop(mayRestart: true) }
  }

  /// Runs started in a row for presses that arrived as a run finished.
  private static var restarts = 0
  private static let maxRestarts = 3

  /// Shuts the engine down and releases the intents whose presses were taken
  /// (`takes` in the notification; all of them after a timeout). A press
  /// queued after the handler took the last one gets a new run, while its
  /// intent keeps waiting, unless the run timed out.
  private static func stop(mayRestart: Bool) {
    timeoutWork?.cancel()
    timeoutWork = nil
    engine?.destroyContext()
    engine = nil
    let restart =
      mayRestart && restarts < maxRestarts && LiveUpdatesBridge.hasQueuedBackgroundActions
    NotificationCenter.default.post(
      name: doneNotification, object: nil,
      userInfo: ["takes": restart ? LiveUpdatesBridge.takeCount : Int.max])
    if restart, LiveUpdatesBridge.startBackgroundHandler().boolValue {
      restarts += 1
    } else {
      restarts = 0
      if restart {
        NotificationCenter.default.post(
          name: doneNotification, object: nil, userInfo: ["takes": Int.max])
      }
    }
  }
}
