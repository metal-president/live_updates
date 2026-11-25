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
    this.icon,
    this.route,
    this.image,
    this.actions = const [],
    this.timer,
    this.metrics = const [],
    this.criticalMetric,
    this.steps,
    this.journey,
    this.publicContent,
    this.endAt,
    this.endedContent,
    this.alert,
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

  /// Icon of the update on both platforms: the small icon of the Android
  /// notification (status bar, Live Update chip) and the icon of the iOS
  /// widget template (thumbnail when there is no [image], and the Dynamic
  /// Island unless [IosLiveUpdateOptions.islandIcon] or [image] is set).
  ///
  /// [AndroidLiveUpdateOptions.smallIcon] and [IosLiveUpdateOptions.icon]
  /// take precedence on their platform. Without any icon, or when the icon
  /// cannot be found, the platform default is used (see [LiveUpdateIcon]).
  final LiveUpdateIcon? icon;

  /// Route delivered to [LiveUpdates.onTap] when the user taps the update.
  final String? route;

  /// Picture shown with the update: a thumbnail in the iOS widget template
  /// and the large icon of the Android notification (not shown on Android 17
  /// with [metrics]).
  ///
  /// On iOS it is shared with the widget extension through an App Group set
  /// up by `create_widget`.
  final LiveUpdateImage? image;

  /// Buttons. Presses arrive on [LiveUpdates.onAction] and
  /// [LiveUpdate.actions] while the app is in the foreground, else at the
  /// background action handler.
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
  /// (except [AndroidLiveUpdateMode.classic]) shows them with `MetricStyle`
  /// instead of the progress bar (and without the body); otherwise Android
  /// adds the number and text metrics to the text (use [timer] for a
  /// countdown there).
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
  /// [AndroidLiveUpdateOptions.progressSegments] or `progressPoints` are
  /// set) and shows the current stage in the text.
  final LiveUpdateSteps? steps;

  /// Where something travels from and to. iOS shows it with
  /// [IosLiveUpdateLayout.journey]; Android shows "from → to" in the text.
  final LiveUpdateJourney? journey;

  /// What the Lock Screen shows instead of this content while the system
  /// hides sensitive content there. `null` shows this content as usual.
  ///
  /// Whether content is hidden depends on the person's device settings
  /// (see [LiveUpdatePublicContent]); the library never hides it on its own.
  ///
  /// [copyWith] keeps it when given `null`, as for the other fields: to
  /// remove it, create a new [LiveUpdateContent] without it.
  final LiveUpdatePublicContent? publicContent;

  /// When the activity this content describes is over, such as the
  /// delivery time. At that time the live update reports
  /// [LiveUpdateState.stale] and [endedContent] replaces this content, even
  /// if the app is not running; without [endedContent] nothing visible
  /// changes. The live update keeps running (it stays in
  /// [LiveUpdates.active]) until the app ends it or the time limit removes
  /// it; an update with new content makes it active again.
  ///
  /// iOS: it is the activity's stale date (unless
  /// [IosLiveUpdateOptions.staleDate] is set, which wins), and the generated
  /// widget shows [endedContent] once the activity is stale. The system
  /// removes a Live Activity after at most eight hours (plus up to four
  /// hours on the Lock Screen).
  ///
  /// Android: an alarm makes the update stale and shows [endedContent] as a
  /// regular notification (no longer ongoing or promoted, so the user can
  /// swipe it away); it is on time with exact alarms
  /// ([LiveUpdates.canScheduleExactly]), otherwise within ten minutes.
  /// [AndroidLiveUpdateOptions.removeAtEnd] removes the notification at
  /// this time instead, and [AndroidLiveUpdateOptions.maxDuration] limits
  /// how long it is shown.
  final DateTime? endAt;

  /// What is shown from [endAt] on, such as "Delivered". `null` keeps this
  /// content.
  final LiveUpdateEndedContent? endedContent;

  /// Alerts the user with this post of the content, on both platforms: the
  /// device plays a sound and may light up the screen or show a banner.
  /// Use it for changes the user must notice, such as "Your order is here",
  /// not for every update.
  ///
  /// iOS shows it with an update (and with a scheduled start), as
  /// [IosLiveUpdateOptions.alert] does, which takes precedence; starting a
  /// Live Activity from the app is always silent. Android plays the sound
  /// and vibration of the notification channel, as
  /// [AndroidLiveUpdateOptions.alert] does; the first post of an update
  /// alerts anyway. Android allows one alert per update every 10 seconds.
  ///
  /// [LiveUpdate.end] never alerts, also with this set on its final
  /// content: [LiveUpdate.update] with the alert first. With this set,
  /// Android alerts whatever [AndroidLiveUpdateOptions.alert] says.
  final LiveUpdateAlert? alert;

  /// iOS-only options.
  final IosLiveUpdateOptions? ios;

  /// Android-only options.
  final AndroidLiveUpdateOptions? android;

  /// Returns a copy with the given fields replaced. A `null` argument keeps
  /// the current value, so a field such as [publicContent] cannot be removed
  /// with it: create a new [LiveUpdateContent] instead. [alert] is the
  /// exception: it belongs to one post, so the copy has it only when given
  /// (the alerts in [ios] and [android] are kept with those options).
  LiveUpdateContent copyWith({
    String? title,
    String? body,
    double? progress,
    LiveUpdateIcon? icon,
    String? route,
    LiveUpdateImage? image,
    List<LiveUpdateAction>? actions,
    LiveUpdateTimer? timer,
    List<LiveUpdateMetric>? metrics,
    int? criticalMetric,
    LiveUpdateSteps? steps,
    LiveUpdateJourney? journey,
    LiveUpdatePublicContent? publicContent,
    DateTime? endAt,
    LiveUpdateEndedContent? endedContent,
    LiveUpdateAlert? alert,
    IosLiveUpdateOptions? ios,
    AndroidLiveUpdateOptions? android,
  }) => LiveUpdateContent(
    title: title ?? this.title,
    body: body ?? this.body,
    progress: progress ?? this.progress,
    icon: icon ?? this.icon,
    route: route ?? this.route,
    image: image ?? this.image,
    actions: actions ?? this.actions,
    timer: timer ?? this.timer,
    metrics: metrics ?? this.metrics,
    criticalMetric: criticalMetric ?? this.criticalMetric,
    steps: steps ?? this.steps,
    journey: journey ?? this.journey,
    publicContent: publicContent ?? this.publicContent,
    endAt: endAt ?? this.endAt,
    endedContent: endedContent ?? this.endedContent,
    // One post's alert: not carried over to the next update.
    alert: alert,
    ios: ios ?? this.ios,
    android: android ?? this.android,
  );

  @override
  bool operator ==(Object other) =>
      other is LiveUpdateContent &&
      other.title == title &&
      other.body == body &&
      other.progress == progress &&
      other.icon == icon &&
      other.route == route &&
      other.image == image &&
      listEquals(other.actions, actions) &&
      other.timer == timer &&
      listEquals(other.metrics, metrics) &&
      other.criticalMetric == criticalMetric &&
      other.steps == steps &&
      other.journey == journey &&
      other.publicContent == publicContent &&
      other.endAt == endAt &&
      other.endedContent == endedContent &&
      other.alert == alert &&
      other.ios == ios &&
      other.android == android;

  @override
  int get hashCode => Object.hash(
    title,
    body,
    progress,
    icon,
    route,
    image,
    Object.hashAll(actions),
    timer,
    Object.hashAll(metrics),
    criticalMetric,
    steps,
    journey,
    publicContent,
    endAt,
    endedContent,
    alert,
    ios,
    android,
  );

  @override
  String toString() =>
      'LiveUpdateContent(title: $title, body: $body, progress: $progress)';
}

/// What a live update shows from [LiveUpdateContent.endAt] on, such as
/// "Delivered" ([LiveUpdateContent.endedContent]).
///
/// Only [title], [body], the icon, [image], the colors and the tap route are
/// shown; progress, the timer, buttons and layout data are left out.
@immutable
final class LiveUpdateEndedContent {
  /// Creates ended content.
  const LiveUpdateEndedContent({
    required this.title,
    this.body,
    this.icon,
    this.image,
  });

  /// Primary text.
  final String title;

  /// Secondary text.
  final String? body;

  /// Icon used instead of [LiveUpdateContent.icon] from
  /// [LiveUpdateContent.endAt] on. Platform options still take precedence
  /// ([IosLiveUpdateOptions.icon], [AndroidLiveUpdateOptions.smallIcon]).
  /// `null` keeps the icon of the content.
  final LiveUpdateIcon? icon;

  /// Picture shown from [LiveUpdateContent.endAt] on, as
  /// [LiveUpdateContent.image] is before. `null` shows no picture. It is
  /// prepared when the content is posted and kept until it is shown.
  final LiveUpdateImage? image;

  @override
  bool operator ==(Object other) =>
      other is LiveUpdateEndedContent &&
      other.title == title &&
      other.body == body &&
      other.icon == icon &&
      other.image == image;

  @override
  int get hashCode => Object.hash(title, body, icon, image);

  @override
  String toString() => 'LiveUpdateEndedContent(title: $title, body: $body)';
}

/// Content shown on the Lock Screen instead of the full [LiveUpdateContent]
/// while the system hides sensitive content there
/// ([LiveUpdateContent.publicContent]).
///
/// Whether that happens depends on the person's device settings; the library
/// never hides content on its own:
///
/// * Android: when the person chose to hide sensitive notification content
///   on the lock screen, the system shows this version of the notification
///   (`Notification.Builder.setPublicVersion`) while the device is locked.
/// * iOS: when the system hides private data of the Live Activity on the
///   Lock Screen (the widget sees the `privacy` or `placeholder` redaction
///   reason), the generated widget shows this content. In tests on iOS 27
///   this happened while the device was locked with Live Activities turned
///   off under Settings > Face ID & Passcode > Allow Access When Locked;
///   the system used either reason.
///
/// Only [title], [body], the icon, the colors and, as chosen with
/// [keepProgress] and [keepTimer], the progress and the timer are shown.
/// Images, buttons, metrics, steps, the journey, extra values and Android's
/// `shortCriticalText` are left out.
@immutable
final class LiveUpdatePublicContent {
  /// Creates public content.
  const LiveUpdatePublicContent({
    required this.title,
    this.body,
    this.keepProgress = true,
    this.keepTimer = true,
  });

  /// Primary text, such as "Delivery in progress".
  final String title;

  /// Secondary text.
  final String? body;

  /// Whether [LiveUpdateContent.progress] is still shown. Progress made only
  /// from [LiveUpdateContent.steps] is not kept, because the steps are left
  /// out.
  final bool keepProgress;

  /// Whether [LiveUpdateContent.timer] (and on Android
  /// [AndroidLiveUpdateOptions.when]) is still shown.
  final bool keepTimer;

  @override
  bool operator ==(Object other) =>
      other is LiveUpdatePublicContent &&
      other.title == title &&
      other.body == body &&
      other.keepProgress == keepProgress &&
      other.keepTimer == keepTimer;

  @override
  int get hashCode => Object.hash(title, body, keepProgress, keepTimer);

  @override
  String toString() => 'LiveUpdatePublicContent(title: $title, body: $body)';
}

/// A timer counted by the system (see [LiveUpdateContent.timer]).
@immutable
final class LiveUpdateTimer {
  /// Counts down to [end]. iOS stops at zero; Android cannot stop a
  /// notification's countdown, so it removes the notification at [end] (see
  /// [AndroidLiveUpdateOptions.removeAtCountdownEnd]).
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
  /// progress segments for up to 21 stages; beyond that it shows a plain
  /// progress bar and the stage in the text.
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
    this.icon,
    this.iosIcon,
    this.androidIcon,
  });

  /// Identifier delivered with the press.
  final String id;

  /// Button label.
  final String title;

  /// Opens the app when pressed. Otherwise the press is handled in the
  /// background: through a `LiveActivityIntent` on iOS and a broadcast on
  /// Android. It reaches [LiveUpdates.onAction] (or that update's
  /// [LiveUpdate.actions]) while the app is in the foreground; otherwise the
  /// background action handler runs it (without one, it waits until the app
  /// listens in the foreground).
  final bool opensApp;

  /// Requires the device to be unlocked before a background press is
  /// handled (Lock Screen presses ask for Face ID / passcode). Use it for
  /// destructive actions such as cancelling an order. Android 12+ and iOS;
  /// ignored for [opensApp] buttons, which always open the app.
  final bool requiresUnlock;

  /// Icon of the button on both platforms. [iosIcon] and [androidIcon]
  /// take precedence on their platform; one that cannot be found is
  /// replaced as described in [LiveUpdateIcon] (no icon on iOS).
  ///
  /// iOS shows it next to the title, such as `LiveUpdateIcon.symbol('xmark')`.
  /// Android 7.0 and later do not show action icons in notifications, but
  /// still pass them on (for example to watches); without one the default
  /// icon is used.
  final LiveUpdateIcon? icon;

  /// Icon of the button on iOS, used instead of [icon].
  final LiveUpdateIcon? iosIcon;

  /// Icon of the button on Android, used instead of [icon].
  final LiveUpdateIcon? androidIcon;

  @override
  bool operator ==(Object other) =>
      other is LiveUpdateAction &&
      other.id == id &&
      other.title == title &&
      other.opensApp == opensApp &&
      other.requiresUnlock == requiresUnlock &&
      other.icon == icon &&
      other.iosIcon == iosIcon &&
      other.androidIcon == androidIcon;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    opensApp,
    requiresUnlock,
    icon,
    iosIcon,
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

/// An icon for [LiveUpdateContent.icon], [IosLiveUpdateOptions.icon],
/// [IosLiveUpdateOptions.islandIcon], [AndroidLiveUpdateOptions.smallIcon],
/// [AndroidLiveUpdateOptions.progressTrackerIcon] and the icons of
/// [LiveUpdateAction].
///
/// An icon is exactly one of: a native resource ([LiveUpdateIcon.native]),
/// a Flutter asset ([LiveUpdateIcon.asset]) or an iOS system symbol
/// ([LiveUpdateIcon.symbol]).
///
/// Each platform uses the first icon that is set, in this order:
///
/// 1. the platform option ([AndroidLiveUpdateOptions.smallIcon] or
///    [IosLiveUpdateOptions.icon]; in the Dynamic Island
///    [IosLiveUpdateOptions.islandIcon] and then [LiveUpdateContent.image]
///    come first),
/// 2. [LiveUpdateContent.icon],
/// 3. the platform default: on Android the drawable named by the
///    `com.ttechapp.live_updates.default_icon` meta-data in the app
///    manifest, else the app icon; on iOS a system symbol.
///
/// When the chosen icon cannot be shown (a resource or asset that does not
/// exist, or a symbol on Android), the platform default is used and a
/// warning is logged. Lower entries of the list are not tried, so a typo
/// does not silently pick another icon.
@immutable
final class LiveUpdateIcon {
  /// A resource of the app: on Android a drawable (or mipmap) such as
  /// `ic_stat_delivery` (the name only, without extension or `@drawable/`),
  /// on iOS an image in the widget extension's asset catalog.
  ///
  /// Android release builds remove resources that the app's own code does
  /// not reference, so list the drawables you name here in a keep file (see
  /// the README).
  const LiveUpdateIcon.native(String this.name)
    : assetName = null,
      symbolName = null;

  /// An image from the app's Flutter assets, such as `assets/delivery.png`.
  ///
  /// On iOS it is scaled down to [maxDimension] pixels and copied into
  /// the App Group shared with the widget extension (set up by
  /// `create_widget`); for remote updates call [LiveUpdates.preloadIcons]
  /// first, because a push does not run the app.
  const LiveUpdateIcon.asset(String this.assetName)
    : name = null,
      symbolName = null;

  /// An iOS system symbol, such as `shippingbox.fill`. Android has no
  /// symbols and uses its default icon instead (so set
  /// [AndroidLiveUpdateOptions.smallIcon] when [LiveUpdateContent.icon] is a
  /// symbol).
  const LiveUpdateIcon.symbol(String this.symbolName)
    : name = null,
      assetName = null;

  /// Longest side in pixels of an [LiveUpdateIcon.asset] icon stored for
  /// the iOS widget (40 points, the largest icon of the widget template, at
  /// 3x). ActivityKit may fail to start an activity whose images are larger
  /// than its presentation.
  static const maxDimension = 120;

  /// Resource name for [LiveUpdateIcon.native].
  final String? name;

  /// Asset name for [LiveUpdateIcon.asset].
  final String? assetName;

  /// Symbol name for [LiveUpdateIcon.symbol].
  final String? symbolName;

  @override
  bool operator ==(Object other) =>
      other is LiveUpdateIcon &&
      other.name == name &&
      other.assetName == assetName &&
      other.symbolName == symbolName;

  @override
  int get hashCode => Object.hash(name, assetName, symbolName);

  @override
  String toString() => switch (this) {
    LiveUpdateIcon(:final name?) => 'LiveUpdateIcon.native($name)',
    LiveUpdateIcon(:final assetName?) => 'LiveUpdateIcon.asset($assetName)',
    _ => 'LiveUpdateIcon.symbol($symbolName)',
  };
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
    this.compactLeading,
    this.compactTrailing,
    this.minimal,
    this.layout,
    this.color,
    this.backgroundColor,
    this.foregroundColor,
    this.icon,
    this.islandIcon,
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

  /// What the generated widget shows on the leading side of the compact
  /// Dynamic Island. `null` (or content that is missing) shows
  /// [IosIslandContent.icon].
  final IosIslandContent? compactLeading;

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
  /// In tests on iOS 27 the default Lock Screen card was black in Light and
  /// Dark Mode alike; Apple's guidelines describe a light background in Light
  /// Mode, which other versions or setups may show. The Dynamic Island is
  /// always black. Pick a color that reads well on dark and on light
  /// backgrounds. While the Always-On display dims the Lock Screen, the
  /// system colors are used.
  final Color? color;

  /// Background of the Lock Screen presentation. `null` keeps the system
  /// background (black in tests on iOS 27; possibly light in Light Mode
  /// elsewhere, see [color]). With a custom
  /// background, also set [foregroundColor].
  final Color? backgroundColor;

  /// Text color of the Lock Screen presentation: the title and other primary
  /// text (and the timer when no [color] is set); secondary text uses it at
  /// 70% opacity. `null` keeps the system text color. The Dynamic Island
  /// keeps its own (dark) colors.
  final Color? foregroundColor;

  /// Icon of the generated widget on iOS, used instead of
  /// [LiveUpdateContent.icon]: the thumbnail when there is no
  /// [LiveUpdateContent.image], and the Dynamic Island when neither
  /// [islandIcon] nor [LiveUpdateContent.image] is set. `null` uses
  /// [LiveUpdateContent.icon]. See [LiveUpdateIcon] for the order and the
  /// default.
  final LiveUpdateIcon? icon;

  /// Icon of the generated widget in the Dynamic Island (the leading side of
  /// the compact and expanded presentations, and [IosIslandContent.icon]),
  /// so that a photo [LiveUpdateContent.image] can stay on the Lock Screen
  /// while the island shows a simple shape. Apple recommends that compact
  /// and minimal content fits a 28-point circle when the island is limited in
  /// width (for example in landscape).
  ///
  /// The island shows the first that is set: [islandIcon],
  /// [LiveUpdateContent.image], [icon], [LiveUpdateContent.icon], the
  /// default symbol. An [islandIcon] that cannot be found shows the default
  /// symbol (see [LiveUpdateIcon]).
  final LiveUpdateIcon? islandIcon;

  @override
  bool operator ==(Object other) =>
      other is IosLiveUpdateOptions &&
      other.staleDate == staleDate &&
      other.relevanceScore == relevanceScore &&
      other.alert == alert &&
      mapEquals(other.extra, extra) &&
      other.compactLeading == compactLeading &&
      other.compactTrailing == compactTrailing &&
      other.minimal == minimal &&
      other.layout == layout &&
      other.color == color &&
      other.backgroundColor == backgroundColor &&
      other.foregroundColor == foregroundColor &&
      other.icon == icon &&
      other.islandIcon == islandIcon;

  @override
  int get hashCode => Object.hash(
    staleDate,
    relevanceScore,
    alert,
    Object.hashAllUnordered(extra.entries.map((e) => (e.key, e.value))),
    compactLeading,
    compactTrailing,
    minimal,
    layout,
    color,
    backgroundColor,
    foregroundColor,
    icon,
    islandIcon,
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
/// ([IosLiveUpdateOptions.compactLeading],
/// [IosLiveUpdateOptions.compactTrailing], [IosLiveUpdateOptions.minimal]).
///
/// Text (title, body, extra) is left out when the island is limited in width
/// (iOS 27, for example in landscape). A customized widget can read the
/// choice as `context.state.compactLeading`, `context.state.compactTrailing`
/// and `context.state.minimal`.
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

  /// The icon ([IosLiveUpdateOptions.islandIcon], else the image or icon,
  /// as described there).
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

/// An alert with a post of a live update ([LiveUpdateContent.alert]).
@immutable
final class LiveUpdateAlert {
  /// Creates an alert. Without [title] or [body], the content's title and
  /// body are used, or those of its [LiveUpdateContent.publicContent] when it
  /// has one, as the alert can show on a locked device.
  const LiveUpdateAlert({this.title, this.body});

  /// Title of the alert on iOS, where the system shows it on devices without
  /// the Dynamic Island and on Apple Watch. Android alerts with the
  /// notification itself, so it is not used there.
  final String? title;

  /// Body of the alert on iOS (see [title]).
  final String? body;

  @override
  bool operator ==(Object other) =>
      other is LiveUpdateAlert && other.title == title && other.body == body;

  @override
  int get hashCode => Object.hash(title, body);

  @override
  String toString() => 'LiveUpdateAlert(title: $title, body: $body)';
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
    this.smallIcon,
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
    this.lockScreenVisibility = AndroidLockScreenVisibility.private,
    this.maxDuration = const Duration(hours: 8),
    this.removeAtEnd = false,
    this.removeAtCountdownEnd = true,
  });

  /// Notification channel id. The channel is created on first use.
  final String channelId;

  /// Notification channel name shown in system settings.
  final String channelName;

  /// Small icon of the notification on Android, used instead of
  /// [LiveUpdateContent.icon]. The system shows it in the status bar, in the
  /// Live Update chip and in the notification header.
  ///
  /// Android draws only the alpha channel of a small icon (in white or in
  /// [color]), so use a single-color drawable or asset with transparency;
  /// a full-color picture such as the app icon becomes a solid shape. See
  /// [LiveUpdateIcon] for the order and the default.
  final LiveUpdateIcon? smallIcon;

  /// Short text for the status bar chip of a promoted Live Update, such as
  /// "5 min". Android shows it in full only when it is shorter than 7
  /// characters; longer text may be cut.
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
  /// messages, alerts, upcoming calendar events or quick access to app
  /// features. Use [AndroidLiveUpdateMode.ongoing] or
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
  /// Shown only with a [LiveUpdateContent.progress] (or
  /// [LiveUpdateContent.steps]), and not on Android 17
  /// when [LiveUpdateContent.metrics] are set (they replace the progress
  /// bar). The same applies
  /// to [progressPoints] and [progressTrackerIcon].
  final List<AndroidProgressSegment> progressSegments;

  /// Marks on the progress bar, such as stops (Android 16+).
  final List<AndroidProgressPoint> progressPoints;

  /// Icon shown at the current position of the progress bar, such as a
  /// car or a parcel (Android 16+). A [LiveUpdateIcon.native] drawable or a
  /// [LiveUpdateIcon.asset]; one that cannot be found (or a symbol) shows no
  /// tracker and logs a warning.
  final LiveUpdateIcon? progressTrackerIcon;

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

  /// How much of the notification a secure lock screen shows. See
  /// [AndroidLockScreenVisibility].
  final AndroidLockScreenVisibility lockScreenVisibility;

  /// How long the notification is shown at most, counted from when the
  /// live update started (later updates do not reset it), even if the app
  /// is not running. The update then reports [LiveUpdateState.ended]. `null`
  /// means no limit. Android 8+.
  ///
  /// The default of eight hours matches iOS, where the system ends a Live
  /// Activity after at most eight hours (and keeps it on the Lock Screen for
  /// up to four more). Content without [LiveUpdateContent.android] and
  /// remote payloads without `maxDurationMillis` use the default too.
  final Duration? maxDuration;

  /// Removes the notification at [LiveUpdateContent.endAt] (exactly, even
  /// if the app is not running) instead of showing
  /// [LiveUpdateContent.endedContent]. Android 8+.
  final bool removeAtEnd;

  /// Removes the notification when the countdown of [LiveUpdateContent.timer]
  /// ends (exactly, even if the app is not running), because an Android
  /// notification's countdown cannot stop at zero and would count below it.
  /// iOS stops the countdown at zero and keeps showing the activity. The
  /// update then reports [LiveUpdateState.ended]. A countdown that is already
  /// over is not shown. Not when [LiveUpdateContent.endedContent] replaces
  /// the content at an [LiveUpdateContent.endAt] up to that time. Pass
  /// `false` to keep the notification, for example when your server updates
  /// it at that time. Android 8+.
  final bool removeAtCountdownEnd;

  @override
  bool operator ==(Object other) =>
      other is AndroidLiveUpdateOptions &&
      other.channelId == channelId &&
      other.channelName == channelName &&
      other.smallIcon == smallIcon &&
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
      other.alert == alert &&
      other.lockScreenVisibility == lockScreenVisibility &&
      other.maxDuration == maxDuration &&
      other.removeAtEnd == removeAtEnd &&
      other.removeAtCountdownEnd == removeAtCountdownEnd;

  @override
  int get hashCode => Object.hash(
    channelId,
    channelName,
    smallIcon,
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
    lockScreenVisibility,
    maxDuration,
    removeAtEnd,
    removeAtCountdownEnd,
  );
}

/// What a secure Android lock screen shows of a notification
/// ([AndroidLiveUpdateOptions.lockScreenVisibility]).
///
/// There is no option to always show the full content: it would override
/// the person's choice to hide sensitive content.
///
/// New values may be added in minor releases.
enum AndroidLockScreenVisibility {
  /// Shows the full notification unless the person hides sensitive
  /// notification content on the lock screen; then
  /// [LiveUpdateContent.publicContent] when set, otherwise only basic
  /// information without the content (`Notification.VISIBILITY_PRIVATE`).
  private,

  /// Always shows nothing of the notification on a secure lock screen,
  /// whatever the person's setting (`Notification.VISIBILITY_SECRET`);
  /// [LiveUpdateContent.publicContent] is not used there.
  secret,
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

  /// Past [LiveUpdateContent.endAt] (on iOS also an
  /// [IosLiveUpdateOptions.staleDate]); update it or end it.
  stale,

  /// Ended by the app or a remote update (on Android also removed by
  /// [AndroidLiveUpdateOptions.timeoutAfter], [AndroidLiveUpdateOptions.maxDuration]
  /// or [AndroidLiveUpdateOptions.removeAtEnd]); may still be visible until
  /// its dismissal time (see [LiveUpdate.end]).
  ended,

  /// Removed from the screen, by the system or the user. On Android not
  /// reported for the notification that stays after [LiveUpdate.end].
  dismissed,
}

/// How Android times a scheduled live update ([LiveUpdates.schedule]).
///
/// Android delivers alarms on time only to apps that may schedule exact
/// alarms: the app has to declare the `SCHEDULE_EXACT_ALARM` permission in
/// its manifest (this package does not), and from Android 14 on the user
/// has to allow it, as it is denied by default for most apps (see
/// [LiveUpdates.canScheduleExactly] and [LiveUpdates.openExactAlarmSettings]).
/// Without it the update is shown within [window] after the scheduled time.
@immutable
final class AndroidScheduleOptions {
  /// Creates Android scheduling options.
  const AndroidScheduleOptions({
    this.exact = true,
    this.window = const Duration(minutes: 10),
  });

  /// Whether to use an exact alarm when the app may schedule one. When
  /// `false`, or when it may not, the update is shown within [window].
  final bool exact;

  /// How late after the scheduled time Android may show the update when
  /// it does not use an exact alarm. Android may stretch short windows
  /// (by default to at least ten minutes) to save battery.
  final Duration window;

  @override
  bool operator ==(Object other) =>
      other is AndroidScheduleOptions &&
      other.exact == exact &&
      other.window == window;

  @override
  int get hashCode => Object.hash(exact, window);

  @override
  String toString() => 'AndroidScheduleOptions(exact: $exact, window: $window)';
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
