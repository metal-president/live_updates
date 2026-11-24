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
