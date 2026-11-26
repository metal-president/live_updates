import ActivityKit
import SwiftUI
import WidgetKit

/// Live Activity UI for live_updates. Generated once by
/// `dart run live_updates:create ios` and yours to edit: running
/// the command again keeps this file (unless you pass --force).
///
/// The building blocks (LiveUpdatesLockScreen, LiveUpdatesCompactTrailing,
/// ...) live in LiveUpdatesViews.swift, which the command updates. Replace
/// any of them with your own views; `context.state` has every field of
/// `LiveUpdateContent`, and `context.state.extra["key"]` the values of
/// `LiveUpdateContent.extra`.
///
/// While the system hides private data on the Lock Screen, the building
/// blocks show `LiveUpdateContent.publicContent` when it is set. A layout of
/// your own should do the same: read `@Environment(\.redactionReasons)` in
/// it and, when `state.liveUpdatesShowsPublic(redactionReasons)` is true, show
/// `LiveUpdatesPublicLockScreen(state: state)` instead.
///
/// From `LiveUpdateContent.endAt` on (the activity is stale), `state` is the
/// `LiveUpdateContent.endedContent` when it is set
/// (`liveUpdatesShown(isStale:)`).
struct LiveUpdatesWidgetLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: LiveUpdatesAttributes.self) { context in
      let state = context.state.liveUpdatesShown(isStale: context.isStale)
      Group {
        switch state.layout {
        // Layouts of your own, chosen with
        // IosLiveUpdateOptions(layout: IosLiveUpdateLayout.custom("name")):
        // case "name": MyLayout(state: state)
        default:
          // The built-in patterns: standard, timer, metrics, stepper, journey.
          LiveUpdatesLockScreen(state: state, activityID: context.activityID)
        }
      }
      .padding()
      .widgetURL(state.liveUpdatesTapURL)
    } dynamicIsland: { context in
      let state = context.state.liveUpdatesShown(isStale: context.isStale)
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          LiveUpdatesIslandIcon(state: state).frame(width: 36, height: 36)
        }
        DynamicIslandExpandedRegion(.trailing) {
          LiveUpdatesExpandedTrailing(state: state)
        }
        DynamicIslandExpandedRegion(.center) {
          LiveUpdatesExpandedCenter(state: state)
        }
        DynamicIslandExpandedRegion(.bottom) {
          LiveUpdatesExpandedBottom(state: state, activityID: context.activityID)
        }
      } compactLeading: {
        // IosLiveUpdateOptions.compactLeading chooses what appears here.
        LiveUpdatesCompactLeading(state: state)
      } compactTrailing: {
        // IosLiveUpdateOptions.compactTrailing chooses what appears here.
        LiveUpdatesCompactTrailing(state: state)
      } minimal: {
        // IosLiveUpdateOptions.minimal chooses what appears here.
        LiveUpdatesMinimal(state: state)
      }
      .keylineTint(state.liveUpdatesKeylineTint)
      .widgetURL(state.liveUpdatesTapURL)
    }
  }
}
