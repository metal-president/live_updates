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
    this.metrics = const [],
    this.criticalMetric,
    this.steps,
    this.journey,
    this.ios,
    this.android,
  }) : assert(progress == null || (progress >= 0 && progress <= 1)),
       assert(criticalMetric == null || criticalMetric >= 0);

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

  /// Values such as a score, a distance or a countdown (up to three are
  /// used). iOS shows them with [IosLiveUpdateLayout.metrics]; Android 17
  /// shows them with `MetricStyle` instead of the progress bar (and without
  /// the body), older versions add the number and text metrics to the text
  /// (use [timer] for a countdown there).
  ///
  /// Keep labels short: Android recommends 10 characters or fewer.
  final List<LiveUpdateMetric> metrics;

  /// Index in [metrics] of the most important one, which Android may show in
  /// the status bar chip of a promoted Live Update. Defaults to the first;
  /// ignored when out of range.
  final int? criticalMetric;

  /// Stages of a process and the current one, such as an order going from
  /// placed to delivered. iOS shows them with [IosLiveUpdateLayout.stepper];
  /// Android 16+ turns them into progress segments and points (unless
  /// [AndroidLiveUpdateOptions.progressSegments] are set) and shows the
  /// current stage in the text.
  final LiveUpdateSteps? steps;

  /// Where something travels from and to. iOS shows it with
  /// [IosLiveUpdateLayout.journey]; Android shows "from → to" in the text.
  final LiveUpdateJourney? journey;

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
    List<LiveUpdateMetric>? metrics,
    int? criticalMetric,
    LiveUpdateSteps? steps,
    LiveUpdateJourney? journey,
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
    metrics: metrics ?? this.metrics,
    criticalMetric: criticalMetric ?? this.criticalMetric,
    steps: steps ?? this.steps,
    journey: journey ?? this.journey,
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
      listEquals(other.metrics, metrics) &&
      other.criticalMetric == criticalMetric &&
      other.steps == steps &&
      other.journey == journey &&
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
    Object.hashAll(metrics),
    criticalMetric,
    steps,
    journey,
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

/// Stages of a process ([LiveUpdateContent.steps]).
@immutable
final class LiveUpdateSteps {
  /// Creates steps; [current] is the index in [labels] of the current stage.
  const LiveUpdateSteps(this.labels, {required this.current})
    : assert(current >= 0);

  /// Short names of the stages, in order.
  ///
  /// iOS draws at most 8 dots, around the current stage; Android 16+ makes
  /// progress segments for up to 21 stages and shows only the text beyond.
  final List<String> labels;

  /// Index of the current stage in [labels].
  final int current;

  @override
  bool operator ==(Object other) =>
      other is LiveUpdateSteps &&
      listEquals(other.labels, labels) &&
      other.current == current;

  @override
  int get hashCode => Object.hash(Object.hashAll(labels), current);
}

/// Where something travels from and to ([LiveUpdateContent.journey]).
@immutable
final class LiveUpdateJourney {
  /// Creates a journey.
  const LiveUpdateJourney({
    required this.from,
    required this.to,
    this.fromDetail,
    this.toDetail,
  });

  /// Starting point, such as a station or an address.
  final String from;

  /// Destination.
  final String to;

  /// Extra line for [from], such as a departure time.
  final String? fromDetail;

  /// Extra line for [to], such as an arrival time.
  final String? toDetail;

  @override
  bool operator ==(Object other) =>
      other is LiveUpdateJourney &&
      other.from == from &&
      other.to == to &&
      other.fromDetail == fromDetail &&
      other.toDetail == toDetail;

  @override
  int get hashCode => Object.hash(from, to, fromDetail, toDetail);
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
    : assert(maxDimension > 0, 'maxDimension must be positive'),
      filePath = null,
      bytes = null,
      url = null;

  /// An image file on the device.
  const LiveUpdateImage.file(String this.filePath, {this.maxDimension = 256})
    : assert(maxDimension > 0, 'maxDimension must be positive'),
      assetName = null,
      bytes = null,
      url = null;

  /// Encoded image bytes (PNG, JPEG, WebP, ...).
  const LiveUpdateImage.memory(Uint8List this.bytes, {this.maxDimension = 256})
    : assert(maxDimension > 0, 'maxDimension must be positive'),
      assetName = null,
      filePath = null,
      url = null;

  /// An image downloaded over HTTPS when the update is posted (redirects
  /// must stay on HTTPS).
  const LiveUpdateImage.network(Uri this.url, {this.maxDimension = 256})
    : assert(maxDimension > 0, 'maxDimension must be positive'),
      assetName = null,
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
    this.layout,
    this.color,
    this.backgroundColor,
    this.foregroundColor,
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

  /// Lock Screen layout of the generated widget: one of the UI patterns in
  /// [IosLiveUpdateLayout]. `null` is [IosLiveUpdateLayout.standard].
  final IosLiveUpdateLayout? layout;

  /// Accent color of the generated widget: progress bars, buttons, the timer
  /// and the Dynamic Island keyline. `null` keeps the system colors. The
  /// Android counterpart is [AndroidLiveUpdateOptions.color].
  ///
  /// The system draws Live Activities on a dark background in both light and
  /// dark mode, so pick a color that reads well on dark. While the Always-On
  /// display dims the Lock Screen, the system colors are used.
  final Color? color;

  /// Background of the Lock Screen presentation. `null` keeps the system
  /// (dark) background. With a light background, also set [foregroundColor].
  final Color? backgroundColor;

  /// Text color of the Lock Screen presentation (title and timer; the body
  /// uses it at 70% opacity). `null` keeps the system's light text. The
  /// Dynamic Island keeps its own (dark) colors.
  final Color? foregroundColor;

  @override
  bool operator ==(Object other) =>
      other is IosLiveUpdateOptions &&
      other.staleDate == staleDate &&
      other.relevanceScore == relevanceScore &&
      other.alert == alert &&
      mapEquals(other.extra, extra) &&
      other.compactTrailing == compactTrailing &&
      other.minimal == minimal &&
      other.layout == layout &&
      other.color == color &&
      other.backgroundColor == backgroundColor &&
      other.foregroundColor == foregroundColor;

  @override
  int get hashCode => Object.hash(
    staleDate,
    relevanceScore,
    alert,
    Object.hashAllUnordered(extra.entries.map((e) => (e.key, e.value))),
    compactTrailing,
    minimal,
    layout,
    color,
    backgroundColor,
    foregroundColor,
  );
}

/// A Lock Screen UI pattern of the generated iOS widget
/// ([IosLiveUpdateOptions.layout]).
///
/// The generated layout file switches on `context.state.layout`, so a
/// [IosLiveUpdateLayout.custom] name can select a layout you add there.
@immutable
final class IosLiveUpdateLayout {
  const IosLiveUpdateLayout._(this.value);

  /// Image, title, body, progress bar and buttons.
  static const standard = IosLiveUpdateLayout._('standard');

  /// A large countdown or stopwatch ([LiveUpdateContent.timer]) next to the
  /// title.
  static const timer = IosLiveUpdateLayout._('timer');

  /// Up to three labeled values side by side ([LiveUpdateContent.metrics]).
  static const metrics = IosLiveUpdateLayout._('metrics');

  /// Stages as dots on a line with the current one highlighted
  /// ([LiveUpdateContent.steps]).
  static const stepper = IosLiveUpdateLayout._('stepper');

  /// From and to with the progress between them
  /// ([LiveUpdateContent.journey], [LiveUpdateContent.progress]).
  static const journey = IosLiveUpdateLayout._('journey');

  /// A layout of your own, handled in the generated layout file.
  const IosLiveUpdateLayout.custom(this.value);

  /// Name read by the widget.
  final String value;

  @override
  bool operator ==(Object other) =>
      other is IosLiveUpdateLayout && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'IosLiveUpdateLayout($value)';
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
    this.mode = AndroidLiveUpdateMode.liveUpdate,
    this.bodySemanticStyle,
    this.progressSemanticStyle,
    this.progressSegments = const [],
    this.progressPoints = const [],
    this.progressTrackerIcon,
    this.timeoutAfter,
    this.alert = false,
  });

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

  /// How the notification is shown on Android 16 and later (older versions
  /// always show a regular ongoing notification with a progress bar).
  ///
  /// Android reserves Live Updates ([AndroidLiveUpdateMode.liveUpdate]) for
  /// ongoing, user-initiated, time-sensitive activities such as navigation,
  /// calls, rides or food delivery, and not for ads, promotions, chat
  /// messages or reminders. Use [AndroidLiveUpdateMode.ongoing] or
  /// [AndroidLiveUpdateMode.classic] for anything else.
  final AndroidLiveUpdateMode mode;

  /// Semantic color of [LiveUpdateContent.body] (Android 17+). The system
  /// picks the actual color, and only applies it to promoted Live Updates.
  /// Not visible on Android 17 when [LiveUpdateContent.metrics] are set,
  /// because the body is not shown.
  final LiveUpdateSemanticStyle? bodySemanticStyle;

  /// Semantic color of the progress bar (Android 17+, promoted Live Updates).
  /// Used when there are no [progressSegments].
  final LiveUpdateSemanticStyle? progressSemanticStyle;

  /// Parts of the progress bar, such as the stages of a delivery (Android
  /// 16+ `ProgressStyle`). Lengths are relative; [LiveUpdateContent.progress]
  /// still runs from 0 to 1 over the whole bar.
  ///
  /// Shown only with a [LiveUpdateContent.progress], and not on Android 17
  /// when [LiveUpdateContent.metrics] are set (they replace the progress
  /// bar). The same applies
  /// to [progressPoints] and [progressTrackerIcon].
  final List<AndroidProgressSegment> progressSegments;

  /// Marks on the progress bar, such as stops (Android 16+).
  final List<AndroidProgressPoint> progressPoints;

  /// Drawable shown at the current position of the progress bar, such as a
  /// car or a parcel (Android 16+).
  final String? progressTrackerIcon;

  /// Removes the notification after this time (at least one minute, counted
  /// from the latest post) even if the app is not running, so a forgotten
  /// update does not stay on screen. A timed-out update reports
  /// [LiveUpdateState.ended], and its key can be started again.
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
      other.mode == mode &&
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
    mode,
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

/// How an Android notification is shown ([AndroidLiveUpdateOptions.mode]).
///
/// New values may be added in minor releases.
enum AndroidLiveUpdateMode {
  /// Android 16+ styles (`ProgressStyle` with segments and points, Android
  /// 17 `MetricStyle`) and a request to promote the notification to a Live
  /// Update (status bar chip, top of the shade). Only for activities that fit
  /// Android's Live Update guidance.
  liveUpdate,

  /// The same Android 16+ styles, without asking for promotion: a regular
  /// ongoing notification.
  ongoing,

  /// A regular ongoing notification with the standard progress bar on every
  /// Android version, as on Android 15 and earlier. Progress segments and
  /// points, semantic colors and `shortCriticalText` are not used, metrics
  /// are added to the text, and the body is always shown.
  classic,
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

/// Kind of value held by an [LiveUpdateMetric].
///
/// New values may be added in minor releases; handle unknown values with a
/// default branch.
enum LiveUpdateMetricKind {
  /// [LiveUpdateMetric.integer].
  integer,

  /// [LiveUpdateMetric.decimal].
  decimal,

  /// [LiveUpdateMetric.text].
  text,

  /// [LiveUpdateMetric.timer].
  timer,

  /// [LiveUpdateMetric.stopwatch].
  stopwatch,

  /// [LiveUpdateMetric.pausedTimer].
  pausedTimer,

  /// [LiveUpdateMetric.pausedStopwatch].
  pausedStopwatch,
}

/// One value of [LiveUpdateContent.metrics].
///
/// Timers and stopwatches are counted by the system, so they keep running
/// without updates from the app.
@immutable
final class LiveUpdateMetric {
  /// A whole number, such as `1979` steps. Android stores it as a 32-bit
  /// integer, so larger values are clamped.
  const LiveUpdateMetric.integer(
    this.label,
    int this.value, {
    this.unit,
    this.semanticStyle,
  }) : kind = LiveUpdateMetricKind.integer,
       fractionDigits = null;

  /// A decimal number, such as `4.2` km, shown with at most
  /// [fractionDigits] digits after the decimal point. NaN and infinite values
  /// are left out.
  const LiveUpdateMetric.decimal(
    this.label,
    double this.value, {
    this.unit,
    this.fractionDigits = 1,
    this.semanticStyle,
  }) : kind = LiveUpdateMetricKind.decimal,
       assert(fractionDigits == null || fractionDigits >= 0);

  /// Short text, such as a gate or a platform number.
  const LiveUpdateMetric.text(
    this.label,
    String this.value, {
    this.unit,
    this.semanticStyle,
  }) : kind = LiveUpdateMetricKind.text,
       fractionDigits = null;

  /// A countdown to [end].
  const LiveUpdateMetric.timer(this.label, DateTime end, {this.semanticStyle})
    : kind = LiveUpdateMetricKind.timer,
      value = end,
      unit = null,
      fractionDigits = null;

  /// Time elapsed since [start].
  const LiveUpdateMetric.stopwatch(
    this.label,
    DateTime start, {
    this.semanticStyle,
  }) : kind = LiveUpdateMetricKind.stopwatch,
       value = start,
       unit = null,
       fractionDigits = null;

  /// A paused countdown with [remaining] time left.
  const LiveUpdateMetric.pausedTimer(
    this.label,
    Duration remaining, {
    this.semanticStyle,
  }) : kind = LiveUpdateMetricKind.pausedTimer,
       value = remaining,
       unit = null,
       fractionDigits = null;

  /// A paused stopwatch showing [elapsed].
  const LiveUpdateMetric.pausedStopwatch(
    this.label,
    Duration elapsed, {
    this.semanticStyle,
  }) : kind = LiveUpdateMetricKind.pausedStopwatch,
       value = elapsed,
       unit = null,
       fractionDigits = null;

  /// What the value means, such as "Distance".
  final String label;

  /// Kind of [value].
  final LiveUpdateMetricKind kind;

  /// An `int`, `double`, `String`, `DateTime` or `Duration`, depending on
  /// [kind].
  final Object value;

  /// Unit shown with a number or text, such as "km".
  final String? unit;

  /// Maximum digits after the decimal point of [LiveUpdateMetricKind.decimal].
  final int? fractionDigits;

  /// Semantic color of the value on a promoted Android 17 Live Update.
  final LiveUpdateSemanticStyle? semanticStyle;

  @override
  bool operator ==(Object other) =>
      other is LiveUpdateMetric &&
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
