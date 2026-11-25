import ActivityKit
import Foundation
import UIKit

/// Objective-C surface over ActivityKit, consumed from Dart through FFIgen.
///
/// Content is exchanged as JSON strings to keep the bridged surface small:
/// the keys of `LiveUpdatesAttributes.ContentState` (written by the Dart
/// `LiveUpdateContentJson`) plus "staleDate" (epoch seconds),
/// "relevanceScore", "enablePushUpdates", "broadcastChannelId" and
/// "alert": {"title", "body", "sound"}.
///
/// Mutable state is only touched on the main thread: Dart calls these methods
/// on the platform (main) thread, and Tasks hop to the main actor before
/// touching it. Handlers are Dart listener blocks, callable from any thread.
///
/// The plugin builds for apps that target iOS 15.0, but Live Activities
/// need iOS 17.2. Below that, `isAvailable` is `false` and Dart uses its
/// no-op backend without calling the rest; if called anyway, methods return
/// empty results, and `start`, `startOrUpdate` and `update` report an error.
@objc(LiveUpdatesBridge)
public final class LiveUpdatesBridge: NSObject {
  private static var tokenTasks: [String: Task<Void, Never>] = [:]
  private static var pushToStartTask: Task<Void, Never>?

  /// Whether this iOS version supports live_updates (iOS 17.2 or later).
  @objc public static func isAvailable() -> Bool {
    if #available(iOS 17.2, *) { return true }
    return false
  }

  /// Error for calls below iOS 17.2.
  private static var unavailableError: NSError {
    NSError(
      domain: "live_updates", code: 3,
      userInfo: [NSLocalizedDescriptionKey: unavailableMessage])
  }

  private static let unavailableMessage = "Live Activities require iOS 17.2 or later."

  /// Whether Live Activities are enabled for this app.
  @objc public static func isSupported() -> Bool {
    guard #available(iOS 17.2, *) else { return false }
    return ActivityAuthorizationInfo().areActivitiesEnabled
  }

  /// Requests a new activity and returns its id.
  @objc public static func start(_ json: String) throws -> String {
    guard #available(iOS 17.2, *) else { throw unavailableError }
    return try request(try Payload.decode(json), key: nil).id
  }

  /// Requests an activity; with `start` (iOS 26+) a scheduled one that the
  /// system starts at that time.
  @available(iOS 17.2, *)
  static func request(_ payload: Payload, key: String?, start: Date? = nil) throws
    -> Activity<LiveUpdatesAttributes>
  {
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
      if let start, #available(iOS 26.0, *) {
        do {
          return try Activity<LiveUpdatesAttributes>.request(
            attributes: LiveUpdatesAttributes(key: key),
            content: payload.content,
            pushType: pushType,
            style: .standard,
            alertConfiguration: payload.alertConfiguration ?? payload.defaultAlertConfiguration,
            start: start
          )
        } catch let error as ActivityAuthorizationError where error == .visibility {
          throw NSError(
            domain: "live_updates", code: 5,
            userInfo: [
              NSLocalizedDescriptionKey:
                "Live updates can only be scheduled while the app is in the foreground."
            ])
        }
      }
      return try Activity<LiveUpdatesAttributes>.request(
        attributes: LiveUpdatesAttributes(key: key),
        content: payload.content,
        pushType: pushType
      )
    } catch let error as NSError where error.domain == "live_updates" {
      throw error
    } catch where pushType != nil {
      throw NSError(
        domain: "live_updates", code: 1,
        userInfo: [
          NSLocalizedDescriptionKey:
            "\(error.localizedDescription) (If the error is about push or entitlements: push "
            + "updates and broadcast channels require the Push Notifications capability "
            + "(aps-environment entitlement) on the Runner target; channels also need Broadcast "
            + "Capability for the App ID.)"
        ])
    }
  }

  /// Updates the activity whose key is `key`, or requests a new one with that
  /// key. An activity with the key that the user dismissed is not replaced
  /// while the system still lists it, so the user does not get it back; one
  /// that ended is replaced. `completion` receives the activity id, or an
  /// error.
  ///
  /// Runs on the main actor so that concurrent calls for one key cannot both
  /// request an activity (the lookup and `request` happen without suspending).
  @objc public static func startOrUpdate(
    _ key: String, json: String, completion: @escaping (String?, String?) -> Void
  ) {
    guard #available(iOS 17.2, *) else { return completion(nil, unavailableMessage) }
    Task { @MainActor in
      do {
        completion(try await startOrUpdateNow(key, payload: try Payload.decode(json)), nil)
      } catch {
        completion(nil, error.localizedDescription)
      }
    }
  }

  /// `startOrUpdate` on the main actor; returns the activity id. Scheduled
  /// activities that have not started are left alone.
  @available(iOS 17.2, *)
  @MainActor
  static func startOrUpdateNow(_ key: String, payload: Payload) async throws -> String {
    let withKey = Activity<LiveUpdatesAttributes>.activities.filter {
      $0.attributes.key == key && !isPending($0)
    }
    if let activity = withKey.first(where: {
      $0.activityState == .active || $0.activityState == .stale
    }) {
      await activity.update(payload.content, alertConfiguration: payload.alertConfiguration)
      return activity.id
    }
    // One the user dismissed is not brought back while the system lists it.
    // Dismissed also covers activities this app ended with an immediate
    // dismissal (or whose dismissal time passed): those do not count.
    if let dismissed = withKey.first(where: {
      $0.activityState == .dismissed && !endedByApp($0.id)
    }) {
      return dismissed.id
    }
    // One that ended (and may still be on the Lock Screen) is replaced, as on
    // Android. The new one is requested first, so a refused request keeps
    // the ended one; then the ended ones are removed.
    let ended = withKey.filter { $0.activityState == .ended }
    let activity = try request(payload, key: key)
    for old in ended { await endNow(old) }
    return activity.id
  }

  /// UserDefaults key with the ids of activities this app ended, so a later
  /// `dismissed` state is not mistaken for the user's dismissal (kept across
  /// launches, pruned to the activities the system still lists).
  static let endedIdsKey = "live_updates.endedIds"
  private static let endedLock = NSLock()

  static func noteEndedByApp(_ id: String) {
    endedLock.lock()
    defer { endedLock.unlock() }
    var ids = Set(UserDefaults.standard.stringArray(forKey: endedIdsKey) ?? [])
    if #available(iOS 17.2, *) {
      let listed = Set(Activity<LiveUpdatesAttributes>.activities.map(\.id))
      ids = ids.filter { listed.contains($0) }
    }
    ids.insert(id)
    UserDefaults.standard.set(Array(ids), forKey: endedIdsKey)
  }

  static func endedByApp(_ id: String) -> Bool {
    endedLock.lock()
    defer { endedLock.unlock() }
    return UserDefaults.standard.stringArray(forKey: endedIdsKey)?.contains(id) ?? false
  }

  /// Ends `activity` and removes it from the screen at once.
  @available(iOS 17.2, *)
  static func endNow(_ activity: Activity<LiveUpdatesAttributes>) async {
    noteEndedByApp(activity.id)
    await activity.end(nil, dismissalPolicy: .immediate)
  }

  /// Whether `activity` is scheduled and has not started yet (iOS 26+).
  @available(iOS 17.2, *)
  static func isPending(_ activity: Activity<LiveUpdatesAttributes>) -> Bool {
    if #available(iOS 26.0, *) { return activity.activityState == .pending }
    return false
  }

  // MARK: Scheduling (LiveUpdatesSchedule.swift)

  /// Whether live updates can be scheduled: iOS 26+ and Live Activities
  /// enabled for this app.
  @objc public static func canSchedule() -> Bool { canScheduleNow() }

  /// Schedules `json` to start with `key` at `at` (epoch seconds), replacing
  /// the schedule with that key. A time that is not in the future starts or
  /// updates it now. `completion` receives an error message or `nil`.
  @objc public static func schedule(
    _ key: String, json: String, at: Double, completion: @escaping (String?) -> Void
  ) { scheduleFromDart(key, json: json, at: at, completion: completion) }

  /// Moves the schedule with `key` to `at`, with `json` as its content when
  /// given (the push setting of the schedule is kept). `completion` receives
  /// an error message or `nil`.
  @objc public static func reschedule(
    _ key: String, json: String?, at: Double, completion: @escaping (String?) -> Void
  ) { rescheduleFromDart(key, json: json, at: at, completion: completion) }

  /// Scheduled live updates that have not started, as a JSON array of
  /// `{"key": String, "at": epoch seconds}`.
  @objc public static func scheduledJson() -> String { scheduledFromDart() }

  /// Cancels every schedule (scheduled activities that have not started).
  @objc public static func cancelAllScheduled(_ completion: @escaping () -> Void) {
    cancelAllScheduledFromDart(completion)
  }

  /// Cancels the schedule with `key`, if any.
  @objc public static func cancelScheduled(_ key: String, completion: @escaping () -> Void) {
    cancelScheduledFromDart(key, completion: completion)
  }

  /// Id of the running activity whose key is `key`.
  @objc public static func idForKey(_ key: String) -> String? {
    guard #available(iOS 17.2, *) else { return nil }
    return findByKey(key)?.id
  }

  /// Key of the activity with `id` (from `startOrUpdate` or the push-to-start
  /// `attributes`), or `nil`.
  @objc public static func keyForId(_ id: String) -> String? {
    guard #available(iOS 17.2, *) else { return nil }
    return Activity<LiveUpdatesAttributes>.activities.first { $0.id == id }?.attributes.key
  }

  @available(iOS 17.2, *)
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
    guard #available(iOS 17.2, *) else { return completion(unavailableMessage) }
    Task {
      do {
        let payload = try Payload.decode(json)
        guard let activity = find(id) else { return completion("Unknown activity \(id)") }
        guard activity.activityState == .active || activity.activityState == .stale else {
          return completion("The live update \(id) has ended")
        }
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
    guard #available(iOS 17.2, *) else { return completion(nil) }
    Task {
      do {
        let finalContent = try json.map { try Payload.decode($0).content }
        guard let activity = find(id) else { return completion(nil) }
        let policy: ActivityUIDismissalPolicy =
          dismissAfter < 0
          ? .default
          : dismissAfter == 0 ? .immediate : .after(Date().addingTimeInterval(dismissAfter))
        // What stays on the Lock Screen has no buttons or running timers, as
        // on Android: the final content, else the content shown last. When
        // nothing needs to change, nil keeps what the system shows (which
        // may be newer than this process's copy, after a push).
        let shown = finalContent ?? activity.content
        let stale = shown.staleDate.map { $0 <= Date() } ?? false
        var state = shown.state.liveUpdatesEnded
        // endedContent shows from endAt on: kept only when it already shows,
        // as Android keeps the ended look it shows (and drops endAt).
        if !stale { state.endedContent = nil }
        let content: ActivityContent<LiveUpdatesAttributes.ContentState>? =
          finalContent == nil && state == shown.state && (stale || shown.staleDate == nil)
          ? nil
          : ActivityContent(
            state: state, staleDate: stale ? shown.staleDate : nil,
            relevanceScore: shown.relevanceScore)
        noteEndedByApp(activity.id)
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

  /// Ids of the activities that are running (not ended or dismissed).
  @objc public static func activeIds() -> [String] {
    guard #available(iOS 17.2, *) else { return [] }
    return Activity<LiveUpdatesAttributes>.activities
      .filter { $0.activityState == .active || $0.activityState == .stale }
      .map(\.id)
  }

  /// Calls `handler` with every push token (hex) of the activity `id`.
  @objc public static func observePushTokens(
    _ id: String, handler: @escaping (String) -> Void
  ) {
    guard #available(iOS 17.2, *), let activity = find(id) else { return }
    tokenTasks[id]?.cancel()
    tokenTasks[id] = Task {
      for await token in activity.pushTokenUpdates {
        handler(token.hexString)
      }
    }
  }

  /// Calls `handler` with every push-to-start token (hex).
  @objc public static func observePushToStartTokens(_ handler: @escaping (String) -> Void) {
    guard #available(iOS 17.2, *) else { return }
    pushToStartTask?.cancel()
    pushToStartTask = Task {
      for await token in Activity<LiveUpdatesAttributes>.pushToStartTokenUpdates {
        handler(token.hexString)
      }
    }
  }

  private static var activityTask: Task<Void, Never>?
  private static var stateTasks: [String: Task<Void, Never>] = [:]

  /// Ends every activity of this app immediately, except scheduled ones
  /// that have not started.
  @objc public static func endAll(_ completion: @escaping () -> Void) {
    guard #available(iOS 17.2, *) else { return completion() }
    Task {
      for activity in Activity<LiveUpdatesAttributes>.activities where !isPending(activity) {
        await endNow(activity)
      }
      completion()
    }
  }

  /// Calls `handler` with `"<state>:<id>"` for activity lifecycle changes:
  /// `started` (including activities started by push-to-start, and
  /// scheduled activities when they start), then `active`, `stale`, `ended`
  /// or `dismissed`. Scheduled activities report nothing before they start.
  ///
  /// Each engine (`engineId`) has its own handler, so a background engine
  /// does not take the events of the app's engine.
  @objc public static func observeActivities(
    _ handler: @escaping (String) -> Void, engineId: Int64
  ) {
    guard #available(iOS 17.2, *) else { return }
    onMain {
      activityHandlers[engineId] = handler
      guard activityTask == nil else { return }
      func emit(_ event: String) {
        DispatchQueue.main.async { activityHandlers.values.forEach { $0(event) } }
      }
      // `activityUpdates` can list an activity again (seen when another
      // activity with its key ends it), so each one is reported once.
      func emitStarted(_ id: String) {
        DispatchQueue.main.async {
          guard startedIds.insert(id).inserted else { return }
          activityHandlers.values.forEach { $0("started:\(id)") }
        }
      }
      func watch(_ activity: Activity<LiveUpdatesAttributes>) {
        guard stateTasks[activity.id] == nil else { return }
        stateTasks[activity.id] = Task {
          var pending = isPending(activity)
          for await state in activity.activityStateUpdates {
            if name(of: state) == "pending" {
              pending = true
              continue
            }
            // A scheduled activity appears when it starts; one cancelled
            // before that never appeared.
            if pending {
              guard state == .active || state == .stale else { break }
              pending = false
              emitStarted(activity.id)
            }
            emit("\(name(of: state)):\(activity.id)")
            // An ended activity stays listed until it is dismissed.
            if state == .dismissed { break }
          }
        }
      }
      Activity<LiveUpdatesAttributes>.activities.forEach {
        if !isPending($0) { startedIds.insert($0.id) }
        watch($0)
      }
      activityTask = Task {
        for await activity in Activity<LiveUpdatesAttributes>.activityUpdates {
          if !isPending(activity) { emitStarted(activity.id) }
          await MainActor.run { watch(activity) }
        }
      }
    }
  }

  private static var activityHandlers: [Int64: (String) -> Void] = [:]
  /// Activities reported as `started` (main thread).
  private static var startedIds: Set<String> = []

  /// Called when an engine goes away: its isolate's handlers are dead, so
  /// presses are queued again and taps wait for the next listener.
  @objc public static func engineDetached(_ engineId: Int64) {
    onMain {
      activityHandlers.removeValue(forKey: engineId)
      tapHandlers.removeValue(forKey: engineId)
      if actionEngine == engineId {
        actionHandler = nil
        actionFilter = nil
        if hasQueuedBackgroundActions { _ = startBackgroundHandler() }
      }
    }
  }

  @available(iOS 17.2, *)
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
  /// Activities whose presses Dart takes; `nil` for all (`onAction`). Other
  /// presses stay queued for the background handler.
  private static var actionFilter: Set<String>?
  private static var actionEngine: Int64 = 0
  private static var activeObserver: NSObjectProtocol?

  /// Calls `handler` with `"<activity id>\n<action id>"` for presses of
  /// `activityIds` (`nil`: all), including
  /// presses queued while Dart was not listening; other presses stay queued
  /// for the background handler.
  @objc public static func observeActions(
    _ handler: @escaping (String) -> Void, activityIds: [String]?, engineId: Int64
  ) {
    onMain {
      actionHandler = handler
      actionEngine = engineId
      actionFilter = activityIds.map(Set.init)
      // Presses wait while the app is in the background; hand them over
      // when it comes back.
      if activeObserver == nil {
        activeObserver = NotificationCenter.default.addObserver(
          forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in drainActions() }
      }
      drainActions()
      if hasQueuedBackgroundActions { _ = startBackgroundHandler() }
    }
  }

  /// Limits the presses Dart takes to those of `activityIds` (`nil`: all).
  @objc public static func setActionFilter(_ activityIds: [String]?, engineId: Int64) {
    onMain {
      guard actionEngine == engineId else { return }
      actionFilter = activityIds.map(Set.init)
      drainActions()
      if hasQueuedBackgroundActions { _ = startBackgroundHandler() }
    }
  }

  /// Queues presses again that reached Dart but no listener took (it
  /// stopped listening in the meantime), for a listener that takes them or
  /// the background handler.
  @objc public static func requeueActions(_ presses: [String]) {
    onMain {
      let defaults = UserDefaults.standard
      // In front: they were pressed before anything queued since.
      defaults.set(
        presses + (defaults.stringArray(forKey: pendingActionsKey) ?? []),
        forKey: pendingActionsKey)
      drainActions()
      if hasQueuedBackgroundActions { _ = startBackgroundHandler() }
    }
  }

  /// Whether the app's Dart listener takes `press`. Not while the app is in
  /// the background: it could be suspended mid-handler, so the background
  /// handler (which the intent waits for) runs it.
  private static func dartTakes(_ press: String) -> Bool {
    guard actionHandler != nil, UIApplication.shared.applicationState == .active else {
      return false
    }
    guard let filter = actionFilter else { return true }
    return filter.contains(String(press.prefix { $0 != "\n" }))
  }

  /// Stops delivering presses to Dart (nothing listens any more): queued and
  /// later presses are run by the background handler.
  @objc public static func unobserveActions(_ engineId: Int64) {
    onMain {
      guard actionEngine == engineId else { return }
      actionHandler = nil
      actionFilter = nil
      if hasQueuedBackgroundActions { _ = startBackgroundHandler() }
    }
  }

  /// Runs `work` on the main thread, where the queue and handlers live.
  private static func onMain(_ work: @escaping () -> Void) {
    if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
  }

  /// Whether presses wait for the background handler (no Dart listener).
  static var hasQueuedBackgroundActions: Bool {
    (UserDefaults.standard.stringArray(forKey: pendingActionsKey) ?? []).contains { !dartTakes($0) }
  }

  /// Hands Dart the queued presses it takes; the rest stay queued.
  static func drainActions() {
    guard let handler = actionHandler else { return }
    let defaults = UserDefaults.standard
    let pending = defaults.stringArray(forKey: pendingActionsKey) ?? []
    let taken = pending.filter(dartTakes)
    guard !taken.isEmpty else { return }
    defaults.set(pending.filter { !dartTakes($0) }, forKey: pendingActionsKey)
    taken.forEach(handler)
  }

  /// Queues a button press and delivers it if Dart listens. Called on the
  /// main thread by `LiveUpdatesActionIntent` (looked up by name, so the
  /// widget extension does not link the plugin) and for open-app URLs.
  ///
  /// Returns a positive number when the background action handler runs the
  /// press: the caller should then wait for a `LiveUpdatesBackgroundDone`
  /// whose `takes` is at least that number (or that has none). 0 otherwise.
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
    guard #available(iOS 17.2, *),
      let activity = find(activityId), !isPending(activity),
      case let state = activity.content.state,
      state.actions.contains(where: { $0.id == actionId })
    else { return false }
    let defaults = UserDefaults.standard
    var pending = defaults.stringArray(forKey: pendingActionsKey) ?? []
    pending.append("\(activityId)\n\(actionId)")
    defaults.set(pending, forKey: pendingActionsKey)
    drainActions()
    if !startBackground {
      // Open-app press: the app's onAction listener should take it. If none
      // does soon after launch, the background handler runs it instead.
      DispatchQueue.main.asyncAfter(deadline: .now() + openAppGrace) {
        drainActions()
        if hasQueuedBackgroundActions { _ = startBackgroundHandler() }
      }
      return 0
    }
    guard hasQueuedBackgroundActions, startBackgroundHandler().boolValue else { return 0 }
    // The intent waits until a run took this press: the next take.
    return NSNumber(value: takeCount + 1)
  }

  /// How many times the background handler took queued presses.
  static var takeCount = 0

  /// Time an app opened by a button gets to start listening to `onAction`.
  private static let openAppGrace: TimeInterval = 5

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
    // Presses a Dart listener of the app takes are left to it.
    defaults.set(pending.filter(dartTakes), forKey: pendingActionsKey)
    takeCount += 1
    return pending.filter { !dartTakes($0) }
  }

  /// Called by the background engine when the handler finished.
  @objc public static func backgroundActionsDone() {
    guard let runner = NSClassFromString("LiveUpdatesBackgroundRunner") as AnyObject? else {
      return
    }
    _ = runner.perform(NSSelectorFromString("finish"))
  }

  static func startBackgroundHandler() -> NSNumber {
    let dispatcher = Int64(UserDefaults.standard.integer(forKey: dispatcherKey))
    guard dispatcher != 0,
      let runner = NSClassFromString("LiveUpdatesBackgroundRunner") as AnyObject?,
      let started = runner.perform(
        NSSelectorFromString("startWithDispatcher:"), with: NSNumber(value: dispatcher)
      )?.takeUnretainedValue() as? NSNumber
    else { return false }
    return started
  }

  private static var tapHandlers: [Int64: (String) -> Void] = [:]
  private static var pendingRoutes: [String] = []

  /// Calls `handler` with the route of every tap, including a tap that
  /// launched the app before Dart subscribed. Each engine has its own.
  @objc public static func observeTaps(_ handler: @escaping (String) -> Void, engineId: Int64) {
    onMain {
      tapHandlers[engineId] = handler
      let pending = pendingRoutes
      pendingRoutes.removeAll()
      pending.forEach(handler)
    }
  }

  @available(iOS 17.2, *)
  private static func find(_ id: String) -> Activity<LiveUpdatesAttributes>? {
    Activity<LiveUpdatesAttributes>.activities.first { $0.id == id }
  }
}

struct Payload: Decodable {
  struct Alert: Decodable {
    var title: String
    var body: String
    var sound: String?
  }

  var title: String
  var body: String?
  var progress: Double?
  var icon: LiveUpdatesIcon?
  var iosIcon: LiveUpdatesIcon?
  var islandIcon: LiveUpdatesIcon?
  var route: String?
  var image: String?
  var actions: [LiveUpdatesAction]?
  var extra: [String: String]?
  var timerStart: Double?
  var timerEnd: Double?
  var compactTrailing: String?
  var compactLeading: String?
  var minimal: String?
  var tintArgb: Int?
  var backgroundArgb: Int?
  var foregroundArgb: Int?
  var layout: String?
  var metrics: [LiveUpdatesMetric]?
  var steps: LiveUpdatesSteps?
  var journey: LiveUpdatesJourney?
  var publicContent: LiveUpdatesPublicContent?
  var endedContent: LiveUpdatesEndedContent?
  var staleDate: Double?
  var relevanceScore: Double?
  var enablePushUpdates: Bool?
  var broadcastChannelId: String?
  var alert: Alert?

  static func decode(_ json: String) throws -> Payload {
    try JSONDecoder().decode(Payload.self, from: Data(json.utf8))
  }

  @available(iOS 17.2, *)
  var content: ActivityContent<LiveUpdatesAttributes.ContentState> {
    ActivityContent(
      state: .init(
        title: title, body: body, progress: progress, icon: icon, iosIcon: iosIcon,
        islandIcon: islandIcon, route: route, image: image, actions: actions ?? [], extra: extra ?? [:],
        timerStart: timerStart, timerEnd: timerEnd,
        compactTrailing: compactTrailing, compactLeading: compactLeading, minimal: minimal,
        tintArgb: tintArgb, backgroundArgb: backgroundArgb, foregroundArgb: foregroundArgb,
        layout: layout, metrics: metrics ?? [], steps: steps, journey: journey,
        publicContent: publicContent, endedContent: endedContent),
      staleDate: staleDate.map { Date(timeIntervalSince1970: $0) },
      relevanceScore: relevanceScore ?? 0
    )
  }

  /// Alert for a scheduled activity's start when the content has none.
  @available(iOS 17.2, *)
  var defaultAlertConfiguration: AlertConfiguration {
    AlertConfiguration(
      title: LocalizedStringResource(stringLiteral: title),
      body: LocalizedStringResource(stringLiteral: body ?? ""),
      sound: .default)
  }

  @available(iOS 17.2, *)
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
    guard #available(iOS 17.2, *) else { return false }
    guard url.scheme?.lowercased() == tapScheme.lowercased() else { return false }
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    func item(_ name: String) -> String? { items.first(where: { $0.name == name })?.value }
    if url.host == "action", let activity = item("activity"), let action = item("action") {
      // URL schemes are not authenticated: only accept an open-app action
      // that the activity actually shows, so other apps cannot forge presses.
      guard
        let shown = find(activity), !isPending(shown),
        case let state = shown.content.state,
        state.actions.contains(where: { $0.id == action && $0.opensApp })
      else { return true }
      queueAction(activity, actionId: action, startBackground: false)
      return true
    }
    guard url.host == "tap", let route = item("route") else { return false }
    // URL schemes are not authenticated: only deliver a route that one of the
    // app's activities actually carries, so other apps cannot inject routes.
    // Not a scheduled activity's route: it is not shown yet.
    guard
      Activity<LiveUpdatesAttributes>.activities.contains(where: {
        $0.content.state.route == route && !isPending($0)
      })
    else { return true }
    if tapHandlers.isEmpty { pendingRoutes.append(route) } else { tapHandlers.values.forEach { $0(route) } }
    return true
  }
}

@available(iOS 16.1, *)
extension LiveUpdatesAttributes.ContentState {
  /// This content as an ended activity shows it: without buttons, the timer
  /// and timer or stopwatch metrics, which would keep running.
  var liveUpdatesEnded: Self {
    var state = self
    state.actions = []
    state.timerStart = nil
    state.timerEnd = nil
    state.metrics = metrics.filter { $0.type != "timer" && $0.type != "stopwatch" }
    return state
  }
}
