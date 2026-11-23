/// Firebase Cloud Messaging integration for live_updates.
library;

import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:live_updates/live_updates.dart';

import 'src/tokens.dart';

export 'src/tokens.dart' show LiveUpdatesToken, LiveUpdatesTokenType;

/// Connects FCM data messages to [LiveUpdates].
///
/// Android: FCM data messages carrying `live_updates_*` keys start, update
/// or end Live Updates through [LiveUpdates.handleRemotePayload]. Call
/// [listen] once for foreground messages and [handleMessage] from your
/// background handler.
///
/// iOS: Live Activities are updated by APNs directly, which FCM can relay.
/// Register the tokens from [tokens] with your server and send pushes with
/// FCM's `apns.live_activity_token` field (or with APNs).
abstract final class LiveUpdatesFcm {
  /// Data key that marks a message as a live_updates message.
  static const eventKey = 'live_updates_event';

  /// Whether [data] is a live_updates message.
  static bool isLiveUpdatesMessage(Map<String, Object?> data) =>
      data.containsKey(eventKey);

  /// Applies [message] if it is a live_updates message. Returns whether it
  /// was handled. Safe to call from a background message handler.
  static Future<bool> handleMessage(RemoteMessage message) =>
      handleData(message.data);

  /// Same as [handleMessage] for a raw data map.
  static Future<bool> handleData(Map<String, Object?> data) async {
    if (!isLiveUpdatesMessage(data)) return false;
    return LiveUpdates.handleRemotePayload(data);
  }

  /// Every token your server needs, as one stream:
  ///
  /// - the Firebase Installation ID ([LiveUpdatesTokenType.fcmInstallationId],
  ///   send to it with `message.fid`) whenever FCM reports a registration;
  ///   call `FirebaseMessaging.instance.register()` in your app to get it,
  /// - optionally the legacy registration token
  ///   ([LiveUpdatesTokenType.fcmRegistrationToken], `message.token`) when
  ///   [includeRegistrationToken] is `true`. Firebase only issues it while
  ///   installation IDs are turned off; with them on, the stream reports an
  ///   error for it instead,
  /// - on iOS, the push-to-start token and the push token of each live
  ///   update that is running or starts later (those started with
  ///   `pushUpdates: true`).
  ///
  /// Send each [LiveUpdatesToken] to your server and keep the latest per
  /// [LiveUpdatesToken.type] (and [LiveUpdatesToken.updateId]). Tokens let
  /// anyone holding them push to this device: send them over an
  /// authenticated connection and do not log them.
  ///
  /// ```dart
  /// LiveUpdatesFcm.tokens().listen(api.registerToken, onError: report);
  /// await FirebaseMessaging.instance.register();
  /// ```
  static Stream<LiveUpdatesToken> tokens({
    FirebaseMessaging? messaging,
    bool includeRegistrationToken = false,
  }) {
    final m = messaging ?? FirebaseMessaging.instance;
    return mergeTokens(
      installationIds: m.onRegistered,
      // The registration token APIs are deprecated in favor of FIDs and fail
      // while installation IDs are turned on; they are only used when the app
      // asks for them.
      // ignore: deprecated_member_use
      initialRegistrationToken: includeRegistrationToken ? m.getToken : null,
      registrationTokenRefresh: includeRegistrationToken
          // ignore: deprecated_member_use
          ? m.onTokenRefresh
          : null,
    );
  }

  /// Handles foreground FCM messages until the subscription is cancelled.
  ///
  /// A live_updates message that cannot be applied (malformed content) is
  /// reported to [onError] instead of becoming an uncaught error; without
  /// [onError] it is printed in debug builds.
  static StreamSubscription<RemoteMessage> listen({
    void Function(Object error, StackTrace stack)? onError,
    @visibleForTesting Stream<RemoteMessage>? messages,
  }) => (messages ?? FirebaseMessaging.onMessage).listen((message) async {
    try {
      await handleMessage(message);
    } on Object catch (error, stack) {
      if (onError != null) {
        onError(error, stack);
      } else {
        debugPrint('live_updates_fcm: could not apply a message: $error');
      }
    }
  });
}
