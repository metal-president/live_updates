import ActivityKit
import Foundation

/// Scheduled live updates (iOS 26+): Live Activities requested with a start
/// date, which the system starts itself.
///
/// ActivityKit keeps a scheduled activity as `.pending` in
/// `Activity.activities` until it starts. It does not expose the start date,
/// and content updates before the start are dropped, so the plugin stores
/// the start date and the request JSON of each scheduled activity
/// (`schedulesKey`) and replaces the activity to change it.
extension LiveUpdatesBridge {
  /// UserDefaults key: activity id -> ["key", "at" (epoch seconds), "json"].
  static let schedulesKey = "live_updates.schedules"

  private static let scheduleUnavailableMessage =
    "Scheduling live updates requires iOS 26 or later."

  /// Whether live updates can be scheduled: iOS 26+ and Live Activities
  /// enabled for this app.
  static func canScheduleNow() -> Bool {
    guard #available(iOS 26.0, *) else { return false }
    return ActivityAuthorizationInfo().areActivitiesEnabled
  }

  /// Schedules `json` to start with `key` at `at` (epoch seconds), replacing
  /// the schedule with that key. A time that is not in the future starts or
  /// updates it now. `completion` receives an error message or `nil`.
  static func scheduleFromDart(
    _ key: String, json: String, at: Double, completion: @escaping (String?) -> Void
  ) {
    guard #available(iOS 26.0, *) else { return completion(scheduleUnavailableMessage) }
    Task { @MainActor in
      do {
        try await scheduleNow(key, json: json, at: Date(timeIntervalSince1970: at))
        completion(nil)
      } catch {
        completion(error.localizedDescription)
      }
    }
  }

  /// Moves the schedule with `key` to `at`, with `json` as its content when
  /// given (the push setting of the schedule is kept).
  static func rescheduleFromDart(
    _ key: String, json: String?, at: Double, completion: @escaping (String?) -> Void
  ) {
    guard #available(iOS 26.0, *) else { return completion(scheduleUnavailableMessage) }
    Task { @MainActor in
      do {
        guard let activity = pendingActivity(key) else {
          return completion("No live update is scheduled with this key.")
        }
        let stored = storedSchedules[activity.id]?["json"] as? String
        let request: String
        if let json {
          request = try keepingPushSetting(of: stored, in: json)
        } else if let stored {
          request = stored
        } else {
          request = try encode(activity.content)
        }
        try await scheduleNow(key, json: request, at: Date(timeIntervalSince1970: at))
        // Unchanged content: its images must now last until the new time.
        if json == nil { keepImages(of: request, until: Date(timeIntervalSince1970: at)) }
        completion(nil)
      } catch {
        completion(error.localizedDescription)
      }
    }
  }

  /// Scheduled live updates that have not started, as a JSON array of
  /// `{"key": String, "at": epoch seconds}`.
  static func scheduledFromDart() -> String {
    var out: [[String: Any]] = []
    if #available(iOS 26.0, *) {
      let stored = pruneSchedules()
      for activity in Activity<LiveUpdatesAttributes>.activities where isPending(activity) {
        guard let key = activity.attributes.key, let at = stored[activity.id]?["at"] as? Double
        else { continue }
        out.append(["key": key, "at": at])
      }
    }
    let data = (try? JSONSerialization.data(withJSONObject: out)) ?? Data("[]".utf8)
    return String(decoding: data, as: UTF8.self)
  }

  /// Cancels the schedule with `key`, if any.
  static func cancelScheduledFromDart(_ key: String, completion: @escaping () -> Void) {
    guard #available(iOS 26.0, *) else { return completion() }
    Task { @MainActor in
      await cancelPending(key)
      completion()
    }
  }

  /// Cancels every scheduled activity that has not started.
  static func cancelAllScheduledFromDart(_ completion: @escaping () -> Void) {
    guard #available(iOS 26.0, *) else { return completion() }
    Task { @MainActor in
      for activity in Activity<LiveUpdatesAttributes>.activities where isPending(activity) {
        scheduleTasks.removeValue(forKey: activity.id)?.cancel()
        await endNow(activity)
        storedSchedules.removeValue(forKey: activity.id)
      }
      completion()
    }
  }

  /// Called when the app starts: watches scheduled activities, and tidies up
  /// after those that started while the app was not running.
  static func resumeSchedules() {
    guard #available(iOS 26.0, *) else { return }
    Task { @MainActor in
      for activity in Activity<LiveUpdatesAttributes>.activities {
        guard storedSchedules[activity.id] != nil else { continue }
        if isPending(activity) {
          watchScheduled(activity)
        } else if let key = activity.attributes.key {
          await scheduleStarted(activity.id, key: key)
        }
      }
      _ = pruneSchedules()
    }
  }

  // MARK: - Internals

  @available(iOS 26.0, *)
  @MainActor
  private static func scheduleNow(_ key: String, json: String, at: Date) async throws {
    let payload = try Payload.decode(json)
    // The new request comes first: if it fails (for example in the
    // background), the earlier schedule stays.
    guard at > Date() else {
      _ = try await startOrUpdateNow(key, payload: payload)
      await cancelPending(key)
      return
    }
    let activity = try request(payload, key: key, start: at)
    var all = storedSchedules
    all[activity.id] = ["key": key, "at": at.timeIntervalSince1970, "json": json]
    storedSchedules = all
    await cancelPending(key, except: activity.id)
    watchScheduled(activity)
  }

  @available(iOS 26.0, *)
  @MainActor
  private static func pendingActivity(_ key: String) -> Activity<LiveUpdatesAttributes>? {
    Activity<LiveUpdatesAttributes>.activities.first {
      $0.attributes.key == key && isPending($0)
    }
  }

  @available(iOS 26.0, *)
  @MainActor
  private static func cancelPending(_ key: String, except kept: String? = nil) async {
    for activity in Activity<LiveUpdatesAttributes>.activities
    where activity.attributes.key == key && isPending(activity) && activity.id != kept {
      scheduleTasks.removeValue(forKey: activity.id)?.cancel()
      await endNow(activity)
      storedSchedules.removeValue(forKey: activity.id)
    }
  }

  @MainActor private static var scheduleTasks: [String: Task<Void, Never>] = [:]

  /// Waits for the scheduled `activity` to start.
  @available(iOS 26.0, *)
  @MainActor
  private static func watchScheduled(_ activity: Activity<LiveUpdatesAttributes>) {
    guard scheduleTasks[activity.id] == nil, let key = activity.attributes.key else { return }
    scheduleTasks[activity.id] = Task { @MainActor in
      for await state in activity.activityStateUpdates where state != .pending {
        scheduleTasks.removeValue(forKey: activity.id)
        if state == .active || state == .stale {
          await scheduleStarted(activity.id, key: key)
        } else {
          storedSchedules.removeValue(forKey: activity.id)
        }
        return
      }
    }
  }

  /// The scheduled activity `id` started: like `startOrUpdate`, it replaces
  /// a running or ended activity with the same key, so the older ones are
  /// ended and removed.
  @available(iOS 26.0, *)
  @MainActor
  private static func scheduleStarted(_ id: String, key: String) async {
    storedSchedules.removeValue(forKey: id)
    for activity in Activity<LiveUpdatesAttributes>.activities
    where activity.id != id && activity.attributes.key == key
      && (activity.activityState == .active || activity.activityState == .stale
        || activity.activityState == .ended)
    {
      await endNow(activity)
    }
  }

  /// Drops stored schedules whose activity no longer waits to start, and
  /// returns the rest.
  @available(iOS 26.0, *)
  private static func pruneSchedules() -> [String: [String: Any]] {
    let pending = Set(
      Activity<LiveUpdatesAttributes>.activities.filter { isPending($0) }.map(\.id))
    let all = storedSchedules
    // Started ones are tidied up by their watcher or resumeSchedules.
    let started = Set(
      Activity<LiveUpdatesAttributes>.activities.filter { !isPending($0) }.map(\.id))
    let kept = all.filter { pending.contains($0.key) || started.contains($0.key) }
    if kept.count != all.count { storedSchedules = kept }
    return kept.filter { pending.contains($0.key) }
  }

  static var storedSchedules: [String: [String: Any]] {
    get {
      UserDefaults.standard.dictionary(forKey: schedulesKey) as? [String: [String: Any]] ?? [:]
    }
    set { UserDefaults.standard.set(newValue, forKey: schedulesKey) }
  }

  /// Protects the images that `json` names (`image`, `endedContent.image`,
  /// `extraImages`)
  /// from the clean-up of unused images (Dart's ImageStore, which deletes
  /// files a day after their modification date) until `date`.
  static func keepImages(of json: String, until date: Date) {
    guard
      let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
    else { return }
    let ended = object["endedContent"] as? [String: Any]
    let extra = (object["extraImages"] as? [String: Any])?.values.compactMap { $0 as? String } ?? []
    for name in [object["image"] as? String, ended?["image"] as? String].compactMap({ $0 }) + extra {
      guard !name.hasPrefix("."), let url = LiveUpdatesImages.url(name),
        let modified = try? FileManager.default.attributesOfItem(atPath: url.path)[
          .modificationDate] as? Date,
        modified < date
      else { continue }
      try? FileManager.default.setAttributes(
        [.modificationDate: date], ofItemAtPath: url.path)
    }
  }

  /// `json` with the push setting of the `stored` request.
  static func keepingPushSetting(of stored: String?, in json: String) throws -> String {
    guard var object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
    else { return json }
    object.removeValue(forKey: "enablePushUpdates")
    if let stored,
      let old = try? JSONSerialization.jsonObject(with: Data(stored.utf8)) as? [String: Any],
      let push = old["enablePushUpdates"]
    {
      object["enablePushUpdates"] = push
    }
    return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
  }

  /// Request JSON for an activity's current content (the content-state keys
  /// plus its stale date and relevance).
  @available(iOS 16.2, *)
  private static func encode(_ content: ActivityContent<LiveUpdatesAttributes.ContentState>)
    throws -> String
  {
    var object =
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(content.state))
      as? [String: Any] ?? [:]
    if let stale = content.staleDate { object["staleDate"] = stale.timeIntervalSince1970 }
    object["relevanceScore"] = content.relevanceScore
    return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
  }
}
