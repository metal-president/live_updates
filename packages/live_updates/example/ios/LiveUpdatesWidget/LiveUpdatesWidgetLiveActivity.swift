import ActivityKit
import SwiftUI
import WidgetKit

/// Live Activity UI for live_updates. Generated once by
/// `dart run live_updates:create_widget` and yours to edit: running
/// create_widget again keeps this file (unless you pass --force).
///
/// The building blocks (LiveUpdatesLockScreen, LiveUpdatesCompactTrailing,
/// ...) live in LiveUpdatesViews.swift, which create_widget updates. Replace
/// any of them with your own views; `context.state` has every field of
/// `LiveUpdateContent`, and `context.state.extra["key"]` the values of
/// `IosLiveUpdateOptions.extra`.
struct LiveUpdatesWidgetLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: LiveUpdatesAttributes.self) { context in
      Group {
        switch context.state.layout {
        // Layouts of your own, chosen with
        // IosLiveUpdateOptions(layout: IosLiveUpdateLayout.custom("name")):
        // case "name": MyLayout(state: context.state)
        default:
          // The built-in patterns: standard, timer, metrics, stepper, journey.
          LiveUpdatesLockScreen(state: context.state, activityID: context.activityID)
        }
      }
      .padding()
      .widgetURL(context.state.liveUpdatesTapURL)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          LiveUpdatesThumbnail(state: context.state).frame(width: 36, height: 36)
        }
        DynamicIslandExpandedRegion(.trailing) {
          LiveUpdatesExpandedTrailing(state: context.state)
        }
        DynamicIslandExpandedRegion(.center) {
          Text(context.state.title).font(.headline).lineLimit(1)
        }
        DynamicIslandExpandedRegion(.bottom) {
          LiveUpdatesExpandedBottom(state: context.state, activityID: context.activityID)
        }
      } compactLeading: {
        LiveUpdatesThumbnail(state: context.state)
      } compactTrailing: {
        // IosLiveUpdateOptions.compactTrailing chooses what appears here.
        LiveUpdatesCompactTrailing(state: context.state)
      } minimal: {
        // IosLiveUpdateOptions.minimal chooses what appears here.
        LiveUpdatesMinimal(state: context.state)
      }
      .keylineTint(context.state.liveUpdatesKeylineTint)
      .widgetURL(context.state.liveUpdatesTapURL)
    }
  }
}
