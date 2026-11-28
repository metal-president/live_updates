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
        // example-only:begin
        case "delivery": ExampleDeliveryLayout(state: state)
        // example-only:end
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

// Xcode previews of the Lock Screen and the Dynamic Island, drawn by this
// file with sample content (in LiveUpdatesViews.swift). Each preview has a
// sample per built-in layout: pick one at the bottom of the canvas. Add a
// sample of your own content to check a layout you add above.
#if DEBUG
  @available(iOS 17.0, *)
  #Preview("Lock Screen", as: .content, using: LiveUpdatesAttributes.preview) {
    LiveUpdatesWidgetLiveActivity()
  } contentStates: {
    LiveUpdatesAttributes.ContentState.previewStandard
    LiveUpdatesAttributes.ContentState.previewTimer
    LiveUpdatesAttributes.ContentState.previewMetrics
    LiveUpdatesAttributes.ContentState.previewStepper
    LiveUpdatesAttributes.ContentState.previewJourney
    // example-only:begin
    LiveUpdatesAttributes.ContentState.previewDelivery
    // example-only:end
  }

  @available(iOS 17.0, *)
  #Preview("Expanded", as: .dynamicIsland(.expanded), using: LiveUpdatesAttributes.preview) {
    LiveUpdatesWidgetLiveActivity()
  } contentStates: {
    LiveUpdatesAttributes.ContentState.previewStandard
    LiveUpdatesAttributes.ContentState.previewTimer
    LiveUpdatesAttributes.ContentState.previewMetrics
    LiveUpdatesAttributes.ContentState.previewStepper
    LiveUpdatesAttributes.ContentState.previewJourney
  }

  @available(iOS 17.0, *)
  #Preview("Compact", as: .dynamicIsland(.compact), using: LiveUpdatesAttributes.preview) {
    LiveUpdatesWidgetLiveActivity()
  } contentStates: {
    LiveUpdatesAttributes.ContentState.previewStandard
    LiveUpdatesAttributes.ContentState.previewTimer
  }

  @available(iOS 17.0, *)
  #Preview("Minimal", as: .dynamicIsland(.minimal), using: LiveUpdatesAttributes.preview) {
    LiveUpdatesWidgetLiveActivity()
  } contentStates: {
    LiveUpdatesAttributes.ContentState.previewStandard
    LiveUpdatesAttributes.ContentState.previewTimer
  }
#endif

// example-only:begin
/// The example app's custom layout ("Custom layout" switch): the same
/// `LiveUpdateContent.extra` and `extraImages` as the Android layouts in
/// res/layout/live_update_delivery*.xml.
struct ExampleDeliveryLayout: View {
  let state: LiveUpdatesAttributes.ContentState
  @Environment(\.redactionReasons) private var redactionReasons
  @Environment(\.isLuminanceReduced) private var luminanceReduced

  var body: some View {
    if state.liveUpdatesShowsPublic(redactionReasons) {
      LiveUpdatesPublicLockScreen(state: state)
    } else {
      let tint = LiveUpdatesPalette(state, luminanceReduced: luminanceReduced).tint
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 12) {
          if let courier = LiveUpdatesPhoto(name: state.extraImages["courier"]) {
            courier.frame(width: 48, height: 48).clipShape(Circle())
          }
          VStack(alignment: .leading, spacing: 2) {
            Text(state.title).font(.headline).lineLimit(1)
            if let status = state.extra["status"] {
              Text(status).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
          }
          Spacer(minLength: 8)
          if let end = state.timerEnd, end * 1000 > Date().timeIntervalSince1970 * 1000 {
            let date = Date(timeIntervalSince1970: end)
            Text(timerInterval: min(Date(), date)...date, countsDown: true)
              .font(.title2.weight(.semibold)).monospacedDigit()
              .multilineTextAlignment(.trailing).frame(maxWidth: 90)
              .foregroundStyle(tint ?? .primary)
          }
        }
        HStack(alignment: .top) {
          value("Distance", state.extra["distance"])
          value("Stops", state.extra["stops"])
          value("Arrives", state.extra["arrival"])
          if let parcel = LiveUpdatesPhoto(name: state.image) {
            parcel.frame(width: 36, height: 36)
          }
        }
        if let progress = state.progress {
          ProgressView(value: min(max(progress, 0), 1)).tint(tint)
        }
      }
    }
  }

  @ViewBuilder private func value(_ label: String, _ value: String?) -> some View {
    if let value {
      VStack(alignment: .leading, spacing: 2) {
        Text(label).font(.caption).foregroundStyle(.secondary)
        Text(value).font(.subheadline.weight(.semibold)).lineLimit(1)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

#if DEBUG
  extension LiveUpdatesAttributes.ContentState {
    /// The "delivery" layout above, with the extra values the app sends.
    static var previewDelivery: Self {
      Self(
        title: "Order #1234", progress: 0.6,
        extra: [
          "status": "The courier is nearby", "distance": "1.6 km", "stops": "1",
          "arrival": "18:30",
        ],
        timerEnd: previewTime(minutes: 15), layout: "delivery")
    }
  }
#endif
// example-only:end
