import ActivityKit
import Foundation

/// Objective-C surface over ActivityKit, consumed from Dart through FFIgen.
///
/// Content is exchanged as JSON strings to keep the bridged surface small:
/// `{"title", "body", "progress", "iconName", "route", "image", "actions",
///   "extra", "staleDate" (epoch seconds), "relevanceScore",
///   "enablePushUpdates", "alert": {"title", "body", "sound"}}`.
///
/// Mutable state is only touched on the main thread: Dart calls these methods
/// on the platform (main) thread, and Tasks hop to the main actor before
/// touching it. Handlers are Dart listener blocks, callable from any thread.
@objc(LiveUpdatesBridge)
public final class LiveUpdatesBridge: NSObject {
  private static var tokenTasks: [String: Task<Void, Never>] = [:]
  private static var pushToStartTask: Task<Void, Never>?

  /// Whether Live Activities are enabled for this app.
  @objc public static func isSupported() -> Bool {
    ActivityAuthorizationInfo().areActivitiesEnabled
  }

  /// Requests a new activity and returns its id.
  @objc public static func start(_ json: String) throws -> String {
    try request(try Payload.decode(json), key: nil)
  }

  private static func request(_ payload: Payload, key: String?) throws -> String {
    let wantsPush = payload.enablePushUpdates ?? false
    var pushType: PushType? = wantsPush ? .token : nil
    if let channel = payload.broadcastChannelId {
      guard #available(iOS 18.0, *) else {
        throw NSError(
          domain: "live_updates", code: 2,
          userInfo: [NSLocalizedDescriptionKey: "Broadcast channels require iOS 18 or later."])
      }
      pushType = .channel(channel)
    }
    do {
      let activity = try Activity<LiveUpdatesAttributes>.request(
        attributes: LiveUpdatesAttributes(key: key),
        content: payload.content,
        pushType: pushType
      )
      return activity.id
    } catch where pushType != nil {
      throw NSError(
        domain: "live_updates", code: 1,
        userInfo: [
          NSLocalizedDescriptionKey:
            "\(error.localizedDescription) Push updates and broadcast channels "
            + "require the Push Notifications capability (aps-environment entitlement) on the "
            + "Runner target; channels also need Broadcast Capability for the App ID."
        ])
    }
  }

  /// Updates the activity whose key is `key`, or requests a new one with that
  /// key. An activity with the key that has ended or was dismissed is not
  /// replaced while the system still lists it, so the user does not get it
  /// back. `completion` receives the activity id, or an error.
  ///
  /// Runs on the main actor so that concurrent calls for one key cannot both
  /// request an activity (the lookup and `request` happen without suspending).
  @objc public static func startOrUpdate(
    _ key: String, json: String, completion: @escaping (String?, String?) -> Void
  ) {
    Task { @MainActor in
      do {
        let payload = try Payload.decode(json)
        if let activity = Activity<LiveUpdatesAttributes>.activities.first(where: {
          $0.attributes.key == key
        }) {
          if activity.activityState == .active || activity.activityState == .stale {
            await activity.update(payload.content, alertConfiguration: payload.alertConfiguration)
          }
          return completion(activity.id, nil)
        }
        completion(try request(payload, key: key), nil)
      } catch {
        completion(nil, error.localizedDescription)
      }
    }
  }

  /// Id of the running activity whose key is `key`.
  @objc public static func idForKey(_ key: String) -> String? {
    findByKey(key)?.id
  }

  /// Key of the activity with `id` (from `startOrUpdate` or the push-to-start
  /// `attributes`), or `nil`.
  @objc public static func keyForId(_ id: String) -> String? {
    Activity<LiveUpdatesAttributes>.activities.first { $0.id == id }?.attributes.key
  }

  private static func findByKey(_ key: String) -> Activity<LiveUpdatesAttributes>? {
    Activity<LiveUpdatesAttributes>.activities.first {
      $0.attributes.key == key && ($0.activityState == .active || $0.activityState == .stale)
    }
  }

  /// Updates the activity with `id`. `completion` receives an error message
  /// or `nil` on success.
  @objc public static func update(
    _ id: String, json: String, completion: @escaping (String?) -> Void
  ) {
    Task {
      do {
        let payload = try Payload.decode(json)
        guard let activity = find(id) else { return completion("Unknown activity \(id)") }
        await activity.update(payload.content, alertConfiguration: payload.alertConfiguration)
        completion(nil)
      } catch {
        completion(error.localizedDescription)
      }
    }
  }

  /// Ends the activity with `id`. `dismissAfter` < 0 uses the system default
  /// policy, 0 dismisses immediately, otherwise seconds from now.
  @objc public static func end(
    _ id: String, json: String?, dismissAfter: Double,
    completion: @escaping (String?) -> Void
  ) {
    Task {
      do {
        let content = try json.map { try Payload.decode($0).content }
        guard let activity = find(id) else { return completion(nil) }
        let policy: ActivityUIDismissalPolicy =
          dismissAfter < 0
          ? .default
          : dismissAfter == 0 ? .immediate : .after(Date().addingTimeInterval(dismissAfter))
        await activity.end(content, dismissalPolicy: policy)
        await MainActor.run { tokenTasks.removeValue(forKey: id)?.cancel() }
        completion(nil)
      } catch {
        completion(error.localizedDescription)
      }
    }
  }

  /// Directory for images shared with the widget, or `nil` when the
  /// `LiveUpdatesAppGroup` Info.plist key is missing or the App Group is not
  /// enabled for this app.
  @objc public static func imageDirectory() -> String? {
    LiveUpdatesImages.directory?.path
  }

  /// Ids of the activities currently known to the system.
  @objc public static func activeIds() -> [String] {
    Activity<LiveUpdatesAttributes>.activities.map(\.id)
  }

  /// Calls `handler` with every push token (hex) of the activity `id`.
  @objc public static func observePushTokens(
    _ id: String, handler: @escaping (String) -> Void
  ) {
    guard let activity = find(id) else { return }
    tokenTasks[id]?.cancel()
    tokenTasks[id] = Task {
      for await token in activity.pushTokenUpdates {
        handler(token.hexString)
      }
    }
  }

  /// Calls `handler` with every push-to-start token (hex).
  @objc public static func observePushToStartTokens(_ handler: @escaping (String) -> Void) {
    pushToStartTask?.cancel()
    pushToStartTask = Task {
      for await token in Activity<LiveUpdatesAttributes>.pushToStartTokenUpdates {
        handler(token.hexString)
      }
    }
  }

  private static var activityTask: Task<Void, Never>?
  private static var stateTasks: [String: Task<Void, Never>] = [:]

  /// Ends every activity of this app immediately.
  @objc public static func endAll(_ completion: @escaping () -> Void) {
    Task {
      for activity in Activity<LiveUpdatesAttributes>.activities {
        await activity.end(nil, dismissalPolicy: .immediate)
      }
      completion()
    }
  }

  /// Calls `handler` with `"<state>:<id>"` for activity lifecycle changes:
  /// `started` (including activities started by push-to-start), then
  /// `active`, `stale`, `ended`, `dismissed` or `pending`.
  @objc public static func observeActivities(_ handler: @escaping (String) -> Void) {
    activityTask?.cancel()
    stateTasks.values.forEach { $0.cancel() }
    stateTasks.removeAll()
    func watch(_ activity: Activity<LiveUpdatesAttributes>) {
      guard stateTasks[activity.id] == nil else { return }
      stateTasks[activity.id] = Task {
        for await state in activity.activityStateUpdates {
          handler("\(name(of: state)):\(activity.id)")
          if state == .ended || state == .dismissed { break }
        }
      }
    }
    Activity<LiveUpdatesAttributes>.activities.forEach(watch)
    activityTask = Task {
      for await activity in Activity<LiveUpdatesAttributes>.activityUpdates {
        handler("started:\(activity.id)")
        await MainActor.run { watch(activity) }
      }
    }
  }

  private static func name(of state: ActivityState) -> String {
    switch state {
    case .active: return "active"
    case .ended: return "ended"
    case .dismissed: return "dismissed"
    case .stale: return "stale"
    case .pending: return "pending"
    @unknown default: return "unknown"
    }
  }

  /// UserDefaults key where presses wait until Dart listens (persisted so a
  /// press that launched the app in the background is not lost).
  static let pendingActionsKey = "live_updates.pendingActions"
  private static var actionHandler: ((String) -> Void)?

  /// Calls `handler` with `"<activity id>\n<action id>"` for every button
  /// press, including presses queued while Dart was not listening.
  @objc public static func observeActions(_ handler: @escaping (String) -> Void) {
    actionHandler = handler
    drainActions()
  }

  static func drainActions() {
    guard let handler = actionHandler else { return }
    let defaults = UserDefaults.standard
    let pending = defaults.stringArray(forKey: pendingActionsKey) ?? []
    defaults.removeObject(forKey: pendingActionsKey)
    pending.forEach(handler)
  }

  /// Queues a button press and delivers it if Dart listens. Called on the
  /// main thread by `LiveUpdatesActionIntent` (looked up by name, so the
  /// widget extension does not link the plugin) and for open-app URLs.
  ///
  /// Returns `true` when the press started the background action handler;
  /// the caller should then wait for `LiveUpdatesBackgroundDone`.
  @objc(enqueueAction:actionId:)
  @discardableResult
  public static func enqueueAction(_ activityId: String, actionId: String) -> NSNumber {
    queueAction(activityId, actionId: actionId, startBackground: true)
  }

  /// Queues a press. Open-app presses pass `startBackground: false`: the app
  /// is coming to the foreground and its `onAction` listener handles them.
  static func queueAction(_ activityId: String, actionId: String, startBackground: Bool)
    -> NSNumber
  {
    // Only accept presses of buttons the activity actually shows.
    guard
      let state = find(activityId)?.content.state,
      state.actions.contains(where: { $0.id == actionId })
    else { return false }
    let defaults = UserDefaults.standard
    var pending = defaults.stringArray(forKey: pendingActionsKey) ?? []
    pending.append("\(activityId)\n\(actionId)")
    defaults.set(pending, forKey: pendingActionsKey)
    if actionHandler != nil || !startBackground {
      drainActions()
      return false
    }
    return startBackgroundHandler()
  }

  // MARK: - Background action handler

  static let dispatcherKey = "live_updates.backgroundDispatcher"
  static let handlerKey = "live_updates.backgroundHandler"

  /// Stores the Dart callback handles of the background action handler.
  @objc public static func setBackgroundActionHandler(_ dispatcher: Int64, handler: Int64) {
    UserDefaults.standard.set(dispatcher, forKey: dispatcherKey)
    UserDefaults.standard.set(handler, forKey: handlerKey)
  }

  /// Raw callback handle of the background handler, or 0.
  @objc public static func backgroundActionHandler() -> Int64 {
    Int64(UserDefaults.standard.integer(forKey: handlerKey))
  }

  /// Removes and returns queued presses as `"<activity id>\n<action id>"`.
  @objc public static func takeQueuedActions() -> [String] {
    // The queue is also written on the main thread (enqueueAction).
    guard Thread.isMainThread else { return DispatchQueue.main.sync { takeQueuedActions() } }
    let defaults = UserDefaults.standard
    let pending = defaults.stringArray(forKey: pendingActionsKey) ?? []
    defaults.removeObject(forKey: pendingActionsKey)
    return pending
  }

  /// Called by the background engine when the handler finished.
  @objc public static func backgroundActionsDone() {
    guard let runner = NSClassFromString("LiveUpdatesBackgroundRunner") as AnyObject? else {
      return
    }
    _ = runner.perform(NSSelectorFromString("finish"))
  }

  private static func startBackgroundHandler() -> NSNumber {
    let dispatcher = Int64(UserDefaults.standard.integer(forKey: dispatcherKey))
    guard dispatcher != 0,
      let runner = NSClassFromString("LiveUpdatesBackgroundRunner") as AnyObject?,
      let started = runner.perform(
        NSSelectorFromString("startWithDispatcher:"), with: NSNumber(value: dispatcher)
      )?.takeUnretainedValue() as? NSNumber
    else { return false }
    return started
  }

  private static var tapHandler: ((String) -> Void)?
  private static var pendingRoutes: [String] = []

  /// Calls `handler` with the route of every tap, including a tap that
  /// launched the app before Dart subscribed.
  @objc public static func observeTaps(_ handler: @escaping (String) -> Void) {
    tapHandler = handler
    let pending = pendingRoutes
    pendingRoutes.removeAll()
    pending.forEach(handler)
  }

  private static func find(_ id: String) -> Activity<LiveUpdatesAttributes>? {
    Activity<LiveUpdatesAttributes>.activities.first { $0.id == id }
  }
}

private struct Payload: Decodable {
  struct Alert: Decodable {
    var title: String
    var body: String
    var sound: String?
  }

  var title: String
  var body: String?
  var progress: Double?
  var iconName: String?
  var route: String?
  var image: String?
  var actions: [LiveUpdatesAction]?
  var extra: [String: String]?
  var timerStart: Double?
  var timerEnd: Double?
  var compactTrailing: String?
  var minimal: String?
  var tintArgb: Int?
  var backgroundArgb: Int?
  var foregroundArgb: Int?
  var staleDate: Double?
  var relevanceScore: Double?
  var enablePushUpdates: Bool?
  var broadcastChannelId: String?
  var alert: Alert?

  static func decode(_ json: String) throws -> Payload {
    try JSONDecoder().decode(Payload.self, from: Data(json.utf8))
  }

  var content: ActivityContent<LiveUpdatesAttributes.ContentState> {
    ActivityContent(
      state: .init(
        title: title, body: body, progress: progress, iconName: iconName,
        route: route, image: image, actions: actions ?? [], extra: extra ?? [:],
        timerStart: timerStart, timerEnd: timerEnd,
        compactTrailing: compactTrailing, minimal: minimal,
        tintArgb: tintArgb, backgroundArgb: backgroundArgb, foregroundArgb: foregroundArgb),
      staleDate: staleDate.map { Date(timeIntervalSince1970: $0) },
      relevanceScore: relevanceScore ?? 0
    )
  }

  var alertConfiguration: AlertConfiguration? {
    alert.map {
      AlertConfiguration(
        title: LocalizedStringResource(stringLiteral: $0.title),
        body: LocalizedStringResource(stringLiteral: $0.body),
        sound: $0.sound.map { .named($0) } ?? .default)
    }
  }
}

extension Data {
  fileprivate var hexString: String { map { String(format: "%02x", $0) }.joined() }
}

// MARK: - Taps

extension LiveUpdatesBridge {
  /// URL scheme used by the widget template's `widgetURL`:
  /// `liveupdates-<app bundle id>://tap?route=<percent-encoded route>`.
  /// It is unique per app; `create_widget` registers it in Info.plist.
  static var tapScheme: String { "liveupdates-" + (Bundle.main.bundleIdentifier ?? "") }

  /// Returns `true` if `url` is a live_updates tap URL.
  @discardableResult
  static func handleURL(_ url: URL) -> Bool {
    guard url.scheme?.lowercased() == tapScheme.lowercased() else { return false }
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    func item(_ name: String) -> String? { items.first(where: { $0.name == name })?.value }
    if url.host == "action", let activity = item("activity"), let action = item("action") {
      // URL schemes are not authenticated: only accept an open-app action
      // that the activity actually shows, so other apps cannot forge presses.
      guard
        let state = find(activity)?.content.state,
        state.actions.contains(where: { $0.id == action && $0.opensApp })
      else { return true }
      queueAction(activity, actionId: action, startBackground: false)
      return true
    }
    guard url.host == "tap", let route = item("route") else { return false }
    // URL schemes are not authenticated: only deliver a route that one of the
    // app's activities actually carries, so other apps cannot inject routes.
    guard Activity<LiveUpdatesAttributes>.activities.contains(where: { $0.content.state.route == route })
    else { return true }
    if let handler = tapHandler { handler(route) } else { pendingRoutes.append(route) }
    return true
  }
}
