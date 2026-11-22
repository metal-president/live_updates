import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show listEquals, mapEquals;
import 'package:meta/meta.dart';

// All model classes are `final` so that new optional fields can be added in
// minor releases without breaking code that would otherwise implement them.

/// Content shown by a live update on every platform.
@immutable
final class LiveUpdateContent {
  /// Creates live update content.
  const LiveUpdateContent({
    required this.title,
    this.body,
    this.progress,
    this.iconName,
    this.route,
    this.image,
    this.actions = const [],
    this.timer,
    this.ios,
    this.android,
  }) : assert(progress == null || (progress >= 0 && progress <= 1));

  /// Primary text.
  final String title;

  /// Secondary text.
  final String? body;

  /// Progress between 0 and 1, or `null` when there is no progress bar.
  final double? progress;

  /// Platform asset name of the icon (an Android drawable or mipmap, or an
  /// image in the iOS widget extension's asset catalog).
  final String? iconName;

  /// Route delivered to [LiveUpdates.onTap] when the user taps the update.
  final String? route;

  /// Picture shown with the update: a thumbnail in the iOS widget template
  /// and the large icon of the Android notification.
  ///
  /// On iOS it is shared with the widget extension through an App Group set
  /// up by `create_widget`.
  final LiveUpdateImage? image;

  /// Buttons. Presses arrive on [LiveUpdates.onAction].
  ///
  /// iOS renders them in the widget template (keep the list short: the whole
  /// content must stay under ActivityKit's 4 KB limit). Android shows up to
  /// three as notification actions.
  final List<LiveUpdateAction> actions;

  /// A countdown or stopwatch that the system keeps running between updates,
  /// such as the time until a delivery arrives. Prefer it to updating a text
  /// every second, which uses up the update budget on both platforms.
  ///
  /// iOS shows it in the widget template; Android shows it as the
  /// notification's chronometer (replacing [AndroidLiveUpdateOptions.when]).
  final LiveUpdateTimer? timer;

  /// iOS-only options.
  final IosLiveUpdateOptions? ios;

  /// Android-only options.
  final AndroidLiveUpdateOptions? android;

  /// Returns a copy with the given fields replaced.
  LiveUpdateContent copyWith({
    String? title,
    String? body,
    double? progress,
    String? iconName,
    String? route,
    LiveUpdateImage? image,
    List<LiveUpdateAction>? actions,
    LiveUpdateTimer? timer,
    IosLiveUpdateOptions? ios,
    AndroidLiveUpdateOptions? android,
  }) => LiveUpdateContent(
    title: title ?? this.title,
    body: body ?? this.body,
    progress: progress ?? this.progress,
    iconName: iconName ?? this.iconName,
    route: route ?? this.route,
    image: image ?? this.image,
    actions: actions ?? this.actions,
    timer: timer ?? this.timer,
    ios: ios ?? this.ios,
    android: android ?? this.android,
  );

  @override
  bool operator ==(Object other) =>
      other is LiveUpdateContent &&
      other.title == title &&
      other.body == body &&
      other.progress == progress &&
      other.iconName == iconName &&
      other.route == route &&
      other.image == image &&
      listEquals(other.actions, actions) &&
      other.timer == timer &&
      other.ios == ios &&
      other.android == android;

  @override
  int get hashCode => Object.hash(
    title,
    body,
    progress,
    iconName,
    route,
    image,
    Object.hashAll(actions),
    timer,
    ios,
    android,
  );

  @override
  String toString() =>
      'LiveUpdateContent(title: $title, body: $body, progress: $progress)';
}

/// A timer counted by the system (see [LiveUpdateContent.timer]).
@immutable
final class LiveUpdateTimer {
  /// Counts down to [end] and stops at zero.
  const LiveUpdateTimer.countdown(DateTime this.end) : start = null;

  /// Counts up from [start].
  const LiveUpdateTimer.stopwatch(DateTime this.start) : end = null;

  /// Start of a stopwatch, `null` for a countdown.
  final DateTime? start;

  /// End of a countdown, `null` for a stopwatch.
  final DateTime? end;

  /// Whether this is a countdown.
  bool get countsDown => end != null;

  @override
  bool operator ==(Object other) =>
      other is LiveUpdateTimer && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// A button on a live update.
@immutable
final class LiveUpdateAction {
  /// Creates an action. [id] is reported in [LiveUpdateActionEvent.actionId].
  const LiveUpdateAction({
    required this.id,
    required this.title,
    this.opensApp = false,
    this.requiresUnlock = false,
    this.iosSystemImage,
    this.androidIcon,
  });

  /// Identifier delivered with the press.
  final String id;

  /// Button label.
  final String title;

  /// Opens the app when pressed. Otherwise the press is handled in the
  /// background: through a `LiveActivityIntent` on iOS and a broadcast on
  /// Android, delivered to Dart while the app runs (or when it next listens).
  final bool opensApp;

  /// Requires the device to be unlocked before a background press is
  /// handled (Lock Screen presses ask for Face ID / passcode). Use it for
  /// destructive actions such as cancelling an order. Android 12+ and iOS;
  /// ignored for [opensApp] buttons, which always open the app.
  final bool requiresUnlock;

  /// SF Symbol shown on iOS, such as `xmark`.
  final String? iosSystemImage;

  /// Drawable name used as the action icon on Android.
  final String? androidIcon;

  @override
  bool operator ==(Object other) =>
      other is LiveUpdateAction &&
      other.id == id &&
      other.title == title &&
      other.opensApp == opensApp &&
      other.requiresUnlock == requiresUnlock &&
      other.iosSystemImage == iosSystemImage &&
      other.androidIcon == androidIcon;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    opensApp,
    requiresUnlock,
    iosSystemImage,
    androidIcon,
  );
}

/// A press of a [LiveUpdateAction].
@immutable
final class LiveUpdateActionEvent {
  /// Creates an event.
  const LiveUpdateActionEvent({required this.updateId, required this.actionId});

  /// [LiveUpdate.id] of the update the button belongs to.
  final String updateId;

  /// [LiveUpdateAction.id] of the pressed button.
  final String actionId;

  @override
  bool operator ==(Object other) =>
      other is LiveUpdateActionEvent &&
      other.updateId == updateId &&
      other.actionId == actionId;

  @override
  int get hashCode => Object.hash(updateId, actionId);

  @override
  String toString() => 'LiveUpdateActionEvent($updateId, $actionId)';
}

/// An image for [LiveUpdateContent.image].
///
/// Images are decoded, scaled to fit [maxDimension] pixels and stored as PNG
/// before being handed to the platform. Identical images are stored once.
@immutable
final class LiveUpdateImage {
  /// An image from the app's assets, such as `assets/courier.png`.
  const LiveUpdateImage.asset(String this.assetName, {this.maxDimension = 256})
    : filePath = null,
      bytes = null,
      url = null;

  /// An image file on the device.
  const LiveUpdateImage.file(String this.filePath, {this.maxDimension = 256})
    : assetName = null,
      bytes = null,
      url = null;

  /// Encoded image bytes (PNG, JPEG, WebP, ...).
  const LiveUpdateImage.memory(Uint8List this.bytes, {this.maxDimension = 256})
    : assetName = null,
      filePath = null,
      url = null;

  /// An image downloaded over HTTP(S) when the update is posted.
  const LiveUpdateImage.network(Uri this.url, {this.maxDimension = 256})
    : assetName = null,
      filePath = null,
      bytes = null;

  /// Asset name for [LiveUpdateImage.asset].
  final String? assetName;

  /// Path for [LiveUpdateImage.file].
  final String? filePath;

  /// Bytes for [LiveUpdateImage.memory].
  final Uint8List? bytes;

  /// URL for [LiveUpdateImage.network].
  final Uri? url;

  /// Longest side in pixels after scaling. Live Activities are rendered with
  /// a tight memory budget, so keep this small.
  final int maxDimension;

  @override
  bool operator ==(Object other) =>
      other is LiveUpdateImage &&
      other.assetName == assetName &&
      other.filePath == filePath &&
      identical(other.bytes, bytes) &&
      other.url == url &&
      other.maxDimension == maxDimension;

  @override
  int get hashCode =>
      Object.hash(assetName, filePath, bytes, url, maxDimension);
}

/// Options that only apply to iOS Live Activities.
@immutable
final class IosLiveUpdateOptions {
  /// Creates iOS options.
  const IosLiveUpdateOptions({
    this.staleDate,
    this.relevanceScore,
    this.alert,
    this.extra = const {},
    this.compactTrailing,
    this.minimal,
    this.color,
    this.backgroundColor,
  });

  /// When the system marks the activity as stale.
  final DateTime? staleDate;

  /// Ordering hint when several activities are active.
  final double? relevanceScore;

  /// Alert to show with an update.
  final IosAlert? alert;

  /// Additional values available to a customized widget as
  /// `context.state.extra`.
  final Map<String, String> extra;

  /// What the generated widget shows on the trailing side of the compact
  /// Dynamic Island. `null` (or content that is missing, such as
  /// [IosIslandContent.progress] without a progress) falls back to the
  /// progress, else the timer, else the title.
  final IosIslandContent? compactTrailing;

  /// What the generated widget shows in the minimal Dynamic Island (when
  /// several activities share it). `null` falls back to the progress, else
  /// the icon.
  final IosIslandContent? minimal;

  /// Accent color of the generated widget: progress bars, buttons, the timer
  /// and the Dynamic Island keyline. `null` keeps the system colors. The
  /// Android counterpart is [AndroidLiveUpdateOptions.color].
  ///
  /// Pass a `CupertinoDynamicColor` (for example
  /// `CupertinoDynamicColor.withBrightness(color: ..., darkColor: ...)`) to
  /// use a different color in dark mode. While the Always-On display dims the
  /// Lock Screen, the system colors are used.
  final Color? color;

  /// Background of the Lock Screen presentation. `null` keeps the system
  /// background. Like [color], a `CupertinoDynamicColor` gives dark mode its
  /// own background; keep the text readable in both modes.
  final Color? backgroundColor;

  @override
  bool operator ==(Object other) =>
      other is IosLiveUpdateOptions &&
      other.staleDate == staleDate &&
      other.relevanceScore == relevanceScore &&
      other.alert == alert &&
      mapEquals(other.extra, extra) &&
      other.compactTrailing == compactTrailing &&
      other.minimal == minimal &&
      other.color == color &&
      other.backgroundColor == backgroundColor;

  @override
  int get hashCode => Object.hash(
    staleDate,
    relevanceScore,
    alert,
    Object.hashAllUnordered(extra.entries.map((e) => (e.key, e.value))),
    compactTrailing,
    minimal,
    color,
    backgroundColor,
  );
}

/// Content for a small Dynamic Island area
/// ([IosLiveUpdateOptions.compactTrailing], [IosLiveUpdateOptions.minimal]).
///
/// Text (title, body, extra) is left out when the island is limited in width
/// (iOS 27 landscape). A customized widget can read the choice as
/// `context.state.compactTrailing` / `context.state.minimal`.
@immutable
final class IosIslandContent {
  const IosIslandContent._(this.value);

  /// A circular progress ring ([LiveUpdateContent.progress]).
  static const progress = IosIslandContent._('progress');

  /// The timer ([LiveUpdateContent.timer]).
  static const timer = IosIslandContent._('timer');

  /// The title.
  static const title = IosIslandContent._('title');

  /// The body.
  static const body = IosIslandContent._('body');

  /// The icon ([LiveUpdateContent.iconName]).
  static const icon = IosIslandContent._('icon');

  /// The value of [IosLiveUpdateOptions.extra] for [key], such as a short
  /// gate number.
  const IosIslandContent.extra(String key) : value = 'extra:$key';

  /// Wire value read by the widget.
  final String value;

  @override
  bool operator ==(Object other) =>
      other is IosIslandContent && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'IosIslandContent($value)';
}

/// An alert presented with an iOS Live Activity update.
@immutable
final class IosAlert {
  /// Creates an alert.
  const IosAlert({required this.title, required this.body, this.sound});

  /// Alert title.
  final String title;

  /// Alert body.
  final String body;

  /// Sound file name, or `null` for the default sound.
  final String? sound;

  @override
  bool operator ==(Object other) =>
      other is IosAlert &&
      other.title == title &&
      other.body == body &&
      other.sound == sound;

  @override
  int get hashCode => Object.hash(title, body, sound);
}

/// Options that only apply to Android notifications.
@immutable
final class AndroidLiveUpdateOptions {
  /// Creates Android options.
  const AndroidLiveUpdateOptions({
    this.channelId = 'live_updates',
    this.channelName = 'Live updates',
    this.shortCriticalText,
    this.color,
    this.when,
    this.showChronometer = false,
    this.requestPromotion = true,
    this.metrics = const [],
    this.criticalMetric,
    this.bodySemanticStyle,
    this.progressSemanticStyle,
    this.progressSegments = const [],
    this.progressPoints = const [],
    this.progressTrackerIcon,
    this.timeoutAfter,
    this.alert = false,
  }) : assert(criticalMetric == null || criticalMetric >= 0);

  /// Notification channel id. The channel is created on first use.
  final String channelId;

  /// Notification channel name shown in system settings.
  final String channelName;

  /// Short text for the status bar chip of a promoted Live Update, such as
  /// "5 min". Android suggests at most 7 characters and may truncate it.
  final String? shortCriticalText;

  /// Accent color.
  final Color? color;

  /// Time shown in the notification, or the chronometer base when
  /// [showChronometer] is set.
  final DateTime? when;

  /// Show a running chronometer based on [when] instead of a timestamp.
  final bool showChronometer;

  /// Ask Android to promote the notification to a Live Update.
  ///
  /// Android reserves Live Updates for ongoing, user-initiated,
  /// time-sensitive activities such as navigation, calls, rides or food
  /// delivery, and not for ads, promotions, chat messages or reminders. Set
  /// this to `false` for anything else; the update then stays a regular
  /// ongoing notification.
  final bool requestPromotion;

  /// Values such as a distance, a speed or a countdown, shown with Android
  /// 17's `MetricStyle` instead of the progress bar. Up to three are used.
  /// Ignored below Android 17, where [LiveUpdateContent.progress] is shown as
  /// usual.
  ///
  /// Android 17's metric template has no room for [LiveUpdateContent.body],
  /// so the body (and [bodySemanticStyle]) is not shown while metrics are
  /// set. Put what users must see in the title or in an
  /// [AndroidMetric.text].
  ///
  /// Keep labels short: Android recommends 10 characters or fewer.
  final List<AndroidMetric> metrics;

  /// Index in [metrics] of the most important metric, which Android may show
  /// in the status bar chip of a promoted Live Update. Defaults to the first;
  /// ignored when out of range.
  final int? criticalMetric;

  /// Semantic color of [LiveUpdateContent.body] (Android 17+). The system
  /// picks the actual color, and only applies it to promoted Live Updates.
  /// Not visible when [metrics] are set, because the body is not shown.
  final LiveUpdateSemanticStyle? bodySemanticStyle;

  /// Semantic color of the progress bar (Android 17+, promoted Live Updates).
  /// Used when there are no [progressSegments].
  final LiveUpdateSemanticStyle? progressSemanticStyle;

  /// Parts of the progress bar, such as the stages of a delivery (Android
  /// 16+ `ProgressStyle`). Lengths are relative; [LiveUpdateContent.progress]
  /// still runs from 0 to 1 over the whole bar.
  ///
  /// Shown only with a [LiveUpdateContent.progress], and not on Android 17
  /// when [metrics] are set (they replace the progress bar). The same applies
  /// to [progressPoints] and [progressTrackerIcon].
  final List<AndroidProgressSegment> progressSegments;

  /// Marks on the progress bar, such as stops (Android 16+).
  final List<AndroidProgressPoint> progressPoints;

  /// Drawable shown at the current position of the progress bar, such as a
  /// car or a parcel (Android 16+).
  final String? progressTrackerIcon;

  /// Removes the notification after this time (at least one minute, counted
  /// from the latest post) even if the app is not running, so a forgotten update does not stay on screen.
  /// Android 8+; on iOS use [IosLiveUpdateOptions.staleDate] and end the
  /// activity.
  final Duration? timeoutAfter;

  /// Play the channel's sound and vibration for this post. By default only
  /// the first post of an update alerts the user. At most one alert per
  /// update every 10 seconds (iOS: [IosLiveUpdateOptions.alert]).
  final bool alert;

  @override
  bool operator ==(Object other) =>
      other is AndroidLiveUpdateOptions &&
      other.channelId == channelId &&
      other.channelName == channelName &&
      other.shortCriticalText == shortCriticalText &&
      other.color == color &&
      other.when == when &&
      other.showChronometer == showChronometer &&
      other.requestPromotion == requestPromotion &&
      listEquals(other.metrics, metrics) &&
      other.criticalMetric == criticalMetric &&
      other.bodySemanticStyle == bodySemanticStyle &&
      other.progressSemanticStyle == progressSemanticStyle &&
      listEquals(other.progressSegments, progressSegments) &&
      listEquals(other.progressPoints, progressPoints) &&
      other.progressTrackerIcon == progressTrackerIcon &&
      other.timeoutAfter == timeoutAfter &&
      other.alert == alert;

  @override
  int get hashCode => Object.hash(
    channelId,
    channelName,
    shortCriticalText,
    color,
    when,
    showChronometer,
    requestPromotion,
    Object.hashAll(metrics),
    criticalMetric,
    bodySemanticStyle,
    progressSemanticStyle,
    Object.hashAll(progressSegments),
    Object.hashAll(progressPoints),
    progressTrackerIcon,
    timeoutAfter,
    alert,
  );
}

/// A part of the Android progress bar
/// ([AndroidLiveUpdateOptions.progressSegments]).
@immutable
final class AndroidProgressSegment {
  /// Creates a segment with a relative [length] (greater than 0).
  const AndroidProgressSegment(this.length, {this.color, this.semanticStyle})
    : assert(length > 0);

  /// Length relative to the other segments.
  final int length;

  /// Color of the segment.
  final Color? color;

  /// Semantic color (Android 17+, promoted Live Updates); wins over [color].
  final LiveUpdateSemanticStyle? semanticStyle;

  @override
  bool operator ==(Object other) =>
      other is AndroidProgressSegment &&
      other.length == length &&
      other.color == color &&
      other.semanticStyle == semanticStyle;

  @override
  int get hashCode => Object.hash(length, color, semanticStyle);
}

/// A mark on the Android progress bar
/// ([AndroidLiveUpdateOptions.progressPoints]).
@immutable
final class AndroidProgressPoint {
  /// Creates a point at [position], between 0 and 1 of the bar.
  const AndroidProgressPoint(this.position, {this.color, this.semanticStyle})
    : assert(position >= 0 && position <= 1);

  /// Position between 0 (start) and 1 (end).
  final double position;

  /// Color of the point.
  final Color? color;

  /// Semantic color (Android 17+, promoted Live Updates); wins over [color].
  final LiveUpdateSemanticStyle? semanticStyle;

  @override
  bool operator ==(Object other) =>
      other is AndroidProgressPoint &&
      other.position == position &&
      other.color == color &&
      other.semanticStyle == semanticStyle;

  @override
  int get hashCode => Object.hash(position, color, semanticStyle);
}

/// Meaning of a color in an Android 17 Live Update. Android chooses the
/// actual color so that it stays consistent across apps.
///
/// New values may be added in minor releases.
enum LiveUpdateSemanticStyle {
  /// Neutral, informational content.
  info,

  /// A safe situation.
  safe,

  /// Caution.
  caution,

  /// Danger: stop.
  danger,
}

/// Kind of value held by an [AndroidMetric].
///
/// New values may be added in minor releases; handle unknown values with a
/// default branch.
enum AndroidMetricKind {
  /// [AndroidMetric.integer].
  integer,

  /// [AndroidMetric.decimal].
  decimal,

  /// [AndroidMetric.text].
  text,

  /// [AndroidMetric.timer].
  timer,

  /// [AndroidMetric.stopwatch].
  stopwatch,

  /// [AndroidMetric.pausedTimer].
  pausedTimer,

  /// [AndroidMetric.pausedStopwatch].
  pausedStopwatch,
}

/// One value of [AndroidLiveUpdateOptions.metrics] (Android 17+).
///
/// Timers and stopwatches are counted by the system, so they keep running
/// without updates from the app.
@immutable
final class AndroidMetric {
  /// A whole number, such as `1979` steps. Android stores it as a 32-bit
  /// integer, so larger values are clamped.
  const AndroidMetric.integer(
    this.label,
    int this.value, {
    this.unit,
    this.semanticStyle,
  }) : kind = AndroidMetricKind.integer,
       fractionDigits = null;

  /// A decimal number, such as `4.2` km, shown with at most
  /// [fractionDigits] digits after the decimal point. NaN and infinite values
  /// are left out.
  const AndroidMetric.decimal(
    this.label,
    double this.value, {
    this.unit,
    this.fractionDigits = 1,
    this.semanticStyle,
  }) : kind = AndroidMetricKind.decimal,
       assert(fractionDigits == null || fractionDigits >= 0);

  /// Short text, such as a gate or a platform number.
  const AndroidMetric.text(
    this.label,
    String this.value, {
    this.unit,
    this.semanticStyle,
  }) : kind = AndroidMetricKind.text,
       fractionDigits = null;

  /// A countdown to [end].
  const AndroidMetric.timer(this.label, DateTime end, {this.semanticStyle})
    : kind = AndroidMetricKind.timer,
      value = end,
      unit = null,
      fractionDigits = null;

  /// Time elapsed since [start].
  const AndroidMetric.stopwatch(
    this.label,
    DateTime start, {
    this.semanticStyle,
  }) : kind = AndroidMetricKind.stopwatch,
       value = start,
       unit = null,
       fractionDigits = null;

  /// A paused countdown with [remaining] time left.
  const AndroidMetric.pausedTimer(
    this.label,
    Duration remaining, {
    this.semanticStyle,
  }) : kind = AndroidMetricKind.pausedTimer,
       value = remaining,
       unit = null,
       fractionDigits = null;

  /// A paused stopwatch showing [elapsed].
  const AndroidMetric.pausedStopwatch(
    this.label,
    Duration elapsed, {
    this.semanticStyle,
  }) : kind = AndroidMetricKind.pausedStopwatch,
       value = elapsed,
       unit = null,
       fractionDigits = null;

  /// What the value means, such as "Distance".
  final String label;

  /// Kind of [value].
  final AndroidMetricKind kind;

  /// An `int`, `double`, `String`, `DateTime` or `Duration`, depending on
  /// [kind].
  final Object value;

  /// Unit shown with a number or text, such as "km".
  final String? unit;

  /// Maximum digits after the decimal point of [AndroidMetricKind.decimal].
  final int? fractionDigits;

  /// Semantic color of the value on a promoted Live Update.
  final LiveUpdateSemanticStyle? semanticStyle;

  @override
  bool operator ==(Object other) =>
      other is AndroidMetric &&
      other.label == label &&
      other.kind == kind &&
      other.value == value &&
      other.unit == unit &&
      other.fractionDigits == fractionDigits &&
      other.semanticStyle == semanticStyle;

  @override
  int get hashCode =>
      Object.hash(label, kind, value, unit, fractionDigits, semanticStyle);
}

/// Lifecycle state of a live update.
///
/// New values may be added in minor releases; handle unknown values with a
/// default branch.
enum LiveUpdateState {
  /// Visible and updatable.
  active,

  /// iOS: past its stale date; update it or end it.
  stale,

  /// Ended by the app or a remote update; may still be visible on iOS until
  /// its dismissal time.
  ended,

  /// Removed from the screen, by the system or the user.
  dismissed,
}

/// A push token issued by the platform.
@immutable
final class LiveUpdatePushToken {
  /// Creates a push token.
  const LiveUpdatePushToken(this.hex);

  /// Token as a lowercase hex string, ready for APNs.
  final String hex;

  @override
  bool operator ==(Object other) =>
      other is LiveUpdatePushToken && other.hex == hex;

  @override
  int get hashCode => hex.hashCode;

  @override
  // The token is a credential for pushing to this device: keep it out of logs.
  String toString() => 'LiveUpdatePushToken(<redacted>)';
}

/// Thrown when the platform rejects a live update operation.
final class LiveUpdateException implements Exception {
  /// Creates an exception with a platform [message].
  const LiveUpdateException(this.message);

  /// Platform-provided description.
  final String message;

  @override
  String toString() => 'LiveUpdateException: $message';
}
