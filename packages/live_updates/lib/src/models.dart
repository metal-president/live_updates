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
    ios,
    android,
  );

  @override
  String toString() =>
      'LiveUpdateContent(title: $title, body: $body, progress: $progress)';
}

/// A button on a live update.
@immutable
final class LiveUpdateAction {
  /// Creates an action. [id] is reported in [LiveUpdateActionEvent.actionId].
  const LiveUpdateAction({
    required this.id,
    required this.title,
    this.opensApp = false,
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
      other.iosSystemImage == iosSystemImage &&
      other.androidIcon == androidIcon;

  @override
  int get hashCode =>
      Object.hash(id, title, opensApp, iosSystemImage, androidIcon);
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

  @override
  bool operator ==(Object other) =>
      other is IosLiveUpdateOptions &&
      other.staleDate == staleDate &&
      other.relevanceScore == relevanceScore &&
      other.alert == alert &&
      mapEquals(other.extra, extra);

  @override
  int get hashCode => Object.hash(
    staleDate,
    relevanceScore,
    alert,
    Object.hashAllUnordered(extra.entries.map((e) => (e.key, e.value))),
  );
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

  /// Ask Android to promote the notification to a Live Update.
  ///
  /// Android reserves Live Updates for ongoing, user-initiated,
  /// time-sensitive activities such as navigation, calls, rides or food
  /// delivery, and not for ads, promotions, chat messages or reminders. Set
  /// this to `false` for anything else; the update then stays a regular
  /// ongoing notification.
  final bool requestPromotion;

  @override
  bool operator ==(Object other) =>
      other is AndroidLiveUpdateOptions &&
      other.channelId == channelId &&
      other.channelName == channelName &&
      other.shortCriticalText == shortCriticalText &&
      other.color == color &&
      other.when == when &&
      other.showChronometer == showChronometer &&
      other.requestPromotion == requestPromotion;

  @override
  int get hashCode => Object.hash(
    channelId,
    channelName,
    shortCriticalText,
    color,
    when,
    showChronometer,
    requestPromotion,
  );
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
