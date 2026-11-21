/// Firebase Cloud Messaging integration for live_updates.
library;

import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:live_updates/live_updates.dart';

/// Connects FCM data messages to [LiveUpdates].
///
/// Android: FCM data messages carrying `live_updates_*` keys start, update
/// or end Live Updates through [LiveUpdates.handleRemotePayload]. Call
/// [listen] once for foreground messages and [handleMessage] from your
/// background handler.
///
/// iOS: Live Activities are updated by APNs directly. Send the tokens from
/// [LiveUpdates.pushToStartTokens] and [LiveUpdate.pushTokens] to your server
/// and use FCM's `apns.live_activity_token` field (or APNs) to deliver.
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

  /// Handles foreground FCM messages until the subscription is cancelled.
  static StreamSubscription<RemoteMessage> listen() =>
      FirebaseMessaging.onMessage.listen(handleMessage);
}
