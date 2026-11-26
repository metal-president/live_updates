import ActivityKit
import Foundation
import Testing
import UIKit

@testable import live_updates

/// Content-state decoding: APNs pushes come from a server and may be
/// incomplete or malformed in parts.
struct ContentStateDecodingTests {
  private func decode(_ json: String) throws -> LiveUpdatesAttributes.ContentState {
    try JSONDecoder().decode(
      LiveUpdatesAttributes.ContentState.self, from: Data(json.utf8))
  }

  @Test func optionalKeysMayBeMissing() throws {
    let state = try decode(#"{"title":"Order"}"#)
    #expect(state.title == "Order")
    #expect(state.metrics.isEmpty)
    #expect(state.steps == nil)
    #expect(state.journey == nil)
    #expect(state.actions.isEmpty)
  }

  @Test func aBadMetricIsSkippedNotTheWholeState() throws {
    let state = try decode(
      #"{"title":"T","metrics":[{"type":"integer","value":2},{"label":"x"},"#
        + #"{"label":"Gate","type":"text","value":"B12"}]}"#)
    #expect(state.metrics.count == 2)  // the one without a type is skipped
    #expect(state.metrics[0].number == 2)
    #expect(state.metrics[0].label == "")
    #expect(state.metrics[1].text == "B12")
  }

  @Test func stepsDefaultTheCurrentStage() throws {
    let state = try decode(#"{"title":"T","steps":{"labels":["A","B"]}}"#)
    #expect(state.steps?.labels == ["A", "B"])
    #expect(state.steps?.current == 0)
  }

  @Test func aMalformedJourneyIsLeftOut() throws {
    let state = try decode(#"{"title":"T","journey":{"from":1}}"#)
    #expect(state.journey == nil)
  }

  @Test func theEndedStateHasNoButtonsOrRunningTimers() throws {
    let state = try decode(
      #"{"title":"Order","progress":0.5,"timerEnd":1893456000,"timerStart":1,"#
        + #""actions":[{"id":"call","title":"Call"}],"#
        + #""metrics":[{"label":"Stops","type":"integer","value":3},"#
        + #"{"label":"ETA","type":"timer","value":1893456000000},"#
        + #"{"label":"Wait","type":"stopwatch","value":1},"#
        + #"{"label":"Left","type":"pausedTimer","value":60000}]}"#)
    #expect(!state.actions.isEmpty)
    let ended = state.liveUpdatesEnded
    #expect(ended.title == "Order")
    #expect(ended.progress == 0.5)
    #expect(ended.actions.isEmpty)
    #expect(ended.timerStart == nil)
    #expect(ended.timerEnd == nil)
    #expect(ended.metrics.map(\.label) == ["Stops", "Left"])
  }

  private func content(_ json: String, staleIn seconds: Double? = nil, now: Date)
    throws -> ActivityContent<LiveUpdatesAttributes.ContentState>
  {
    ActivityContent(
      state: try decode(json), staleDate: seconds.map { now.addingTimeInterval($0) },
      relevanceScore: 0)
  }

  @Test func endKeepsWhatTheSystemShowsWhenNothingChanges() throws {
    let now = Date()
    let shown = try content(#"{"title":"Order","progress":0.5}"#, now: now)
    #expect(LiveUpdatesBridge.endedContent(final: nil, shown: shown, now: now) == nil)
    #expect(LiveUpdatesBridge.endedContent(final: nil, shown: nil, now: now) == nil)
    // A stale date without endedContent (endAt alone, or ios.staleDate) stays.
    let dated = try content(#"{"title":"Order"}"#, staleIn: 600, now: now)
    #expect(LiveUpdatesBridge.endedContent(final: nil, shown: dated, now: now) == nil)
    let final = LiveUpdatesBridge.endedContent(final: dated, shown: shown, now: now)
    #expect(final?.staleDate == dated.staleDate)
  }

  @Test func endStripsButtonsAndTimersFromTheShownContent() throws {
    let now = Date()
    let shown = try content(
      #"{"title":"Order","timerEnd":1893456000,"actions":[{"id":"a","title":"A"}]}"#,
      now: now)
    let ended = try #require(LiveUpdatesBridge.endedContent(final: nil, shown: shown, now: now))
    #expect(ended.state.title == "Order")
    #expect(ended.state.actions.isEmpty)
    #expect(ended.state.timerEnd == nil)
  }

  @Test func endDropsEndedContentNotShownYetButKeepsOneShown() throws {
    let now = Date()
    let json = #"{"title":"Order","endedContent":{"title":"Delivered"}}"#
    let coming = try content(json, staleIn: 600, now: now)
    let ended = try #require(LiveUpdatesBridge.endedContent(final: nil, shown: coming, now: now))
    #expect(ended.state.endedContent == nil)
    #expect(ended.staleDate == nil)
    let past = try content(json, staleIn: -60, now: now)
    #expect(LiveUpdatesBridge.endedContent(final: nil, shown: past, now: now) == nil)
  }

  @Test func extraImagesDecode() throws {
    let state = try decode(#"{"title":"T","extraImages":{"map":"lu_1.png"}}"#)
    #expect(state.extraImages == ["map": "lu_1.png"])
    // Malformed: left out, not the whole state, and one bad entry alone.
    #expect(try decode(#"{"title":"T","extraImages":3}"#).extraImages.isEmpty)
    #expect(
      try decode(#"{"title":"T","extraImages":{"map":"lu_1.png","bad":3}}"#).extraImages
        == ["map": "lu_1.png"])
    #expect(try decode(#"{"title":"T"}"#).extraImages.isEmpty)
  }

  @Test func extraDecodesAndMayBeMissing() throws {
    #expect(try decode(#"{"title":"T","extra":{"gate":"B12"}}"#).extra == ["gate": "B12"])
    // Sent only when it has values (0.5.0).
    #expect(try decode(#"{"title":"T"}"#).extra.isEmpty)
  }

  @Test func endedContentDecodes() throws {
    let state = try decode(#"{"title":"T","endedContent":{"title":"Done","body":"Enjoy"}}"#)
    #expect(state.endedContent == LiveUpdatesEndedContent(title: "Done", body: "Enjoy"))
    #expect(try decode(#"{"title":"T"}"#).endedContent == nil)
  }

  @Test func endedIconAndImageDecode() throws {
    let state = try decode(
      #"{"title":"T","endedContent":{"title":"Done","icon":{"symbol":"checkmark"},"image":"lu_b.png"}}"#)
    #expect(state.endedContent?.icon == LiveUpdatesIcon(symbol: "checkmark"))
    #expect(state.endedContent?.image == "lu_b.png")
    let bad = try decode(#"{"title":"T","endedContent":{"title":"Done","icon":3,"image":[]}}"#)
    #expect(bad.endedContent == LiveUpdatesEndedContent(title: "Done"))
  }

  @Test func aMalformedEndedContentIsLeftOut() throws {
    #expect(try decode(#"{"title":"T","endedContent":{"body":"x"}}"#).endedContent == nil)
    let state = try decode(#"{"title":"T","endedContent":{"title":"Done","body":3}}"#)
    #expect(state.endedContent == LiveUpdatesEndedContent(title: "Done"))
  }

  @Test func theTitleIsRequired() {
    #expect(throws: (any Error).self) { try decode(#"{"body":"no title"}"#) }
  }

  @Test func iconsDecodePerKey() throws {
    let state = try decode(
      #"{"title":"T","icon":{"asset":"assets/a.png"},"iosIcon":{"native":"pin"},"#
        + #""islandIcon":{"symbol":"shippingbox"},"#
        + #""actions":[{"id":"x","title":"X","icon":{"symbol":"xmark"},"androidIcon":{"native":"ic"}}]}"#)
    #expect(state.icon == LiveUpdatesIcon(asset: "assets/a.png"))
    #expect(state.iosIcon == LiveUpdatesIcon(native: "pin"))
    #expect(state.islandIcon == LiveUpdatesIcon(symbol: "shippingbox"))
    #expect(state.actions[0].icon == LiveUpdatesIcon(symbol: "xmark"))
    #expect(state.actions[0].iosIcon == nil)
  }

  @Test func aMalformedIconIsLeftOut() throws {
    let state = try decode(#"{"title":"T","icon":"pin","islandIcon":{"symbol":3}}"#)
    #expect(state.icon == nil)
    #expect(state.islandIcon == nil)
  }

  @Test func publicContentDecodesWithDefaults() throws {
    let state = try decode(#"{"title":"T","publicContent":{"title":"Delivery"}}"#)
    #expect(state.publicContent == LiveUpdatesPublicContent(title: "Delivery"))
    #expect(state.publicContent?.keepProgress == true)
    #expect(state.publicContent?.keepTimer == true)
    let full = try decode(
      #"{"title":"T","publicContent":{"title":"P","body":"B","keepProgress":false,"keepTimer":false}}"#)
    #expect(
      full.publicContent
        == LiveUpdatesPublicContent(title: "P", body: "B", keepProgress: false, keepTimer: false))
  }

  @Test func contentWithoutPublicContentStillDecodes() throws {
    #expect(try decode(#"{"title":"T"}"#).publicContent == nil)
  }

  @Test func aMalformedPublicContentStillHidesTheFullContent() throws {
    let hidden = LiveUpdatesPublicContent(title: "", keepProgress: false, keepTimer: false)
    let state = try decode(#"{"title":"T","publicContent":{"body":"no title"}}"#)
    #expect(state.title == "T")
    #expect(state.publicContent == hidden)
    #expect(try decode(#"{"title":"T","publicContent":"x"}"#).publicContent == hidden)
    #expect(try decode(#"{"title":"T","publicContent":null}"#).publicContent == nil)
  }

  @Test func aMalformedPublicBodyIsLeftOutNotThePublicContent() throws {
    let state = try decode(
      #"{"title":"T","publicContent":{"title":"Delivery","body":123,"keepProgress":null}}"#)
    #expect(state.publicContent == LiveUpdatesPublicContent(title: "Delivery"))
  }

  @Test func keepFlagsThatAreNotBooleansHideProgressAndTimer() throws {
    let state = try decode(
      #"{"title":"T","publicContent":{"title":"P","keepProgress":0,"keepTimer":"false"}}"#)
    #expect(
      state.publicContent
        == LiveUpdatesPublicContent(title: "P", keepProgress: false, keepTimer: false))
  }

  @Test func publicContentRoundTrips() throws {
    let state = LiveUpdatesAttributes.ContentState(
      title: "T", publicContent: LiveUpdatesPublicContent(title: "P", keepTimer: false))
    let data = try JSONEncoder().encode(state)
    #expect(try JSONDecoder().decode(LiveUpdatesAttributes.ContentState.self, from: data) == state)
  }

  @Test func assetIconFileNameMatchesDart() {
    // Same value as IconStore.fileName('assets/parcel.png') in Dart.
    let url = LiveUpdatesImages.iconURL(asset: "assets/parcel.png")
    #expect(url == nil || url?.lastPathComponent == "e036be2e00f1bd26358db437e998432d.png")
    #expect(url == nil || url?.deletingLastPathComponent().lastPathComponent == "icons")
  }
}

/// Button press routing between the app's Dart listeners and the background
/// handler. Uses the bridge's real queue, so the tests run one at a time.
/// Engine ids 1001 and 1002 stay clear of the host app's own engine.
@MainActor
@Suite(.serialized)
struct PressRoutingTests {
  init() {
    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: LiveUpdatesBridge.pendingActionsKey)
    // No background handler: queued presses stay in the queue for checking.
    defaults.removeObject(forKey: LiveUpdatesBridge.dispatcherKey)
    LiveUpdatesBridge.engineDetached(1001)
    LiveUpdatesBridge.engineDetached(1002)
  }

  private var queued: [String] {
    UserDefaults.standard.stringArray(forKey: LiveUpdatesBridge.pendingActionsKey) ?? []
  }

  /// Presses go to Dart only while the app is active (the test host is).
  private var appActive: Bool { UIApplication.shared.applicationState == .active }

  @Test func aPerUpdateListenerTakesOnlyItsPresses() async throws {
    try #require(appActive)
    var got: [String] = []
    LiveUpdatesBridge.observeActions({ got.append($0) }, activityIds: ["a"], engineId: 1001)
    LiveUpdatesBridge.requeueActions(["a\nx", "b\ny"])
    #expect(got == ["a\nx"])
    #expect(queued == ["b\ny"])
    // The background handler takes what the app does not.
    let before = LiveUpdatesBridge.takeCount
    #expect(LiveUpdatesBridge.takeQueuedActions() == ["b\ny"])
    #expect(LiveUpdatesBridge.takeCount == before + 1)
  }

  @Test func wideningTheFilterHandsOverQueuedPresses() async throws {
    try #require(appActive)
    var got: [String] = []
    LiveUpdatesBridge.observeActions({ got.append($0) }, activityIds: ["a"], engineId: 1001)
    LiveUpdatesBridge.requeueActions(["b\ny"])
    #expect(got.isEmpty)
    // Another engine cannot change this engine's filter.
    LiveUpdatesBridge.setActionFilter(nil, engineId: 1002)
    #expect(got.isEmpty)
    LiveUpdatesBridge.setActionFilter(nil, engineId: 1001)
    #expect(got == ["b\ny"])
  }

  @Test func requeuedPressesGoFirst() async throws {
    UserDefaults.standard.set(["u\nsecond"], forKey: LiveUpdatesBridge.pendingActionsKey)
    LiveUpdatesBridge.requeueActions(["u\nfirst"])
    #expect(queued == ["u\nfirst", "u\nsecond"])
  }

  @Test func aDetachedEngineNoLongerTakesPresses() async throws {
    try #require(appActive)
    var got: [String] = []
    LiveUpdatesBridge.observeActions({ got.append($0) }, activityIds: nil, engineId: 1001)
    LiveUpdatesBridge.engineDetached(1002)  // another engine: still listening
    LiveUpdatesBridge.requeueActions(["a\nx"])
    #expect(got == ["a\nx"])
    LiveUpdatesBridge.engineDetached(1001)
    LiveUpdatesBridge.requeueActions(["a\ny"])
    #expect(got == ["a\nx"])
    #expect(queued == ["a\ny"])
  }

  @Test func unobservingLeavesPressesForTheBackground() async throws {
    try #require(appActive)
    var got: [String] = []
    LiveUpdatesBridge.observeActions({ got.append($0) }, activityIds: nil, engineId: 1001)
    LiveUpdatesBridge.unobserveActions(1002)  // not the owner: ignored
    LiveUpdatesBridge.requeueActions(["a\nx"])
    LiveUpdatesBridge.unobserveActions(1001)
    LiveUpdatesBridge.requeueActions(["a\ny"])
    #expect(got == ["a\nx"])
    #expect(queued == ["a\ny"])
  }
}

/// URLs opened from other apps are not authenticated.
@MainActor
struct ForgedURLTests {
  init() {
    UserDefaults.standard.removeObject(forKey: LiveUpdatesBridge.pendingActionsKey)
  }

  @Test func otherSchemesAreNotHandled() {
    #expect(!LiveUpdatesBridge.handleURL(URL(string: "https://example.com/tap?route=/x")!))
  }

  @Test func aPressForAnUnknownActivityIsDropped() {
    let url = URL(
      string: LiveUpdatesBridge.tapScheme + "://action?activity=forged&action=cancel")!
    #expect(LiveUpdatesBridge.handleURL(url))
    #expect(UserDefaults.standard.stringArray(forKey: LiveUpdatesBridge.pendingActionsKey) == nil)
  }

  @Test func aRouteNoActivityCarriesIsNotDelivered() {
    var routes: [String] = []
    LiveUpdatesBridge.observeTaps({ routes.append($0) }, engineId: 1001)
    let url = URL(string: LiveUpdatesBridge.tapScheme + "://tap?route=/evil")!
    #expect(LiveUpdatesBridge.handleURL(url))
    #expect(routes.isEmpty)
    LiveUpdatesBridge.engineDetached(1001)
  }
}

/// Scheduling helpers that run without requesting activities.
struct ScheduleTests {
  private func object(_ json: String) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
  }

  @Test func newContentKeepsThePushSettingOfTheSchedule() throws {
    let merged = try LiveUpdatesBridge.keepingPushSetting(
      of: #"{"title":"Old","enablePushUpdates":true}"#,
      in: #"{"title":"New","enablePushUpdates":false}"#)
    let result = try object(merged)
    #expect(result["title"] as? String == "New")
    #expect(result["enablePushUpdates"] as? Bool == true)
  }

  @Test func withoutAStoredSettingNewContentHasNone() throws {
    let merged = try LiveUpdatesBridge.keepingPushSetting(
      of: nil, in: #"{"title":"New","enablePushUpdates":true}"#)
    #expect(try object(merged)["enablePushUpdates"] == nil)
  }

  @Test func reschedulingKeepsTheImagesOfTheScheduledContent() throws {
    let directory = try #require(LiveUpdatesImages.directory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let name = "lu_test_keep.png"
    let url = directory.appendingPathComponent(name)
    try Data([1]).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSinceNow: -2 * 86_400)], ofItemAtPath: url.path)
    let until = Date(timeIntervalSinceNow: 5 * 86_400)
    LiveUpdatesBridge.keepImages(
      of: #"{"title":"A","endedContent":{"title":"B","image":"\#(name)"}}"#, until: until)
    let modified = try #require(
      FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
    #expect(abs(modified.timeIntervalSince(until)) < 1)
  }

  @Test func namesOutsideTheImageFilesAreNotTouched() throws {
    let directory = try #require(LiveUpdatesImages.directory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(".hidden_test")
    try Data([1]).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let old = Date(timeIntervalSinceNow: -2 * 86_400)
    try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: url.path)
    LiveUpdatesBridge.keepImages(
      of: #"{"title":"A","image":".hidden_test","endedContent":{"title":"B","image":"../x"}}"#,
      until: Date(timeIntervalSinceNow: 86_400))
    let modified = try #require(
      FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
    #expect(abs(modified.timeIntervalSince(old)) < 1)
  }

  @Test func nothingScheduledIsAnEmptyList() throws {
    UserDefaults.standard.removeObject(forKey: LiveUpdatesBridge.schedulesKey)
    let list = try JSONSerialization.jsonObject(
      with: Data(LiveUpdatesBridge.scheduledJson().utf8))
    #expect((list as? [Any])?.isEmpty == true)
  }

  @Test func canScheduleNeedsIOS26() {
    if #unavailable(iOS 26.0) {
      #expect(!LiveUpdatesBridge.canSchedule())
    }
  }

  @Test func rescheduleWithoutAScheduleReportsAnError() async {
    let message = await withCheckedContinuation { done in
      LiveUpdatesBridge.reschedule("no-such-key", json: nil, at: 0) { done.resume(returning: $0) }
    }
    #expect(message != nil)
  }
}
