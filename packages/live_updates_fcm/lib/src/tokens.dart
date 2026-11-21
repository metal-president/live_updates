import 'dart:async';

import 'package:live_updates/live_updates.dart';
import 'package:meta/meta.dart';

/// What a [LiveUpdatesToken] is for.
///
/// New values may be added in minor releases; handle unknown values with a
/// default branch.
enum LiveUpdatesTokenType {
  /// Firebase Installation ID of this app instance, the recommended FCM send
  /// target (`message.fid`). Emitted after the app calls
  /// `FirebaseMessaging.instance.register()`.
  fcmInstallationId,

  /// Legacy FCM registration token (`message.token`). Only emitted when
  /// [LiveUpdatesFcm.tokens] is called with `includeRegistrationToken: true`.
  fcmRegistrationToken,

  /// iOS push-to-start token: starts a Live Activity remotely
  /// (`apns.live_activity_token` with `"event": "start"`).
  pushToStart,

  /// iOS push token of one running Live Activity: updates or ends it
  /// (`apns.live_activity_token` with `"event": "update"` or `"end"`).
  activity,
}

/// A token to register with your server, from [LiveUpdatesFcm.tokens].
@immutable
final class LiveUpdatesToken {
  /// Creates a token.
  const LiveUpdatesToken({
    required this.type,
    required this.value,
    this.updateId,
  });

  /// What the token is for.
  final LiveUpdatesTokenType type;

  /// The token. FCM values are opaque strings; APNs tokens are hex.
  final String value;

  /// [LiveUpdate.id] for [LiveUpdatesTokenType.activity] tokens, else `null`.
  final String? updateId;

  @override
  bool operator ==(Object other) =>
      other is LiveUpdatesToken &&
      other.type == type &&
      other.value == value &&
      other.updateId == updateId;

  @override
  int get hashCode => Object.hash(type, value, updateId);

  @override
  String toString() =>
      'LiveUpdatesToken(${type.name}${updateId == null ? '' : ', $updateId'})';
}

/// Merges FCM and live update tokens into one stream.
///
/// Listens to the FCM token and its refreshes, iOS push-to-start tokens, and
/// the push tokens of every live update that is running or starts later.
/// Each distinct token is emitted once per subscription.
@internal
Stream<LiveUpdatesToken> mergeTokens({
  required Stream<String> installationIds,
  Future<String?> Function()? initialRegistrationToken,
  Stream<String>? registrationTokenRefresh,
}) {
  late final StreamController<LiveUpdatesToken> controller;
  final subscriptions = <StreamSubscription<Object?>>[];
  final watchedUpdates = <String>{};
  final seen = <LiveUpdatesToken>{};

  void emit(LiveUpdatesToken token) {
    if (seen.add(token) && !controller.isClosed) controller.add(token);
  }

  void watch(LiveUpdate update) {
    if (!watchedUpdates.add(update.id)) return;
    subscriptions.add(
      update.pushTokens.listen(
        (t) => emit(
          LiveUpdatesToken(
            type: LiveUpdatesTokenType.activity,
            value: t.hex,
            updateId: update.id,
          ),
        ),
        onError: controller.addError,
      ),
    );
  }

  controller = StreamController<LiveUpdatesToken>.broadcast(
    onListen: () {
      void Function(String?) fcm(LiveUpdatesTokenType type) => (token) {
        if (token != null && token.isNotEmpty) {
          emit(LiveUpdatesToken(type: type, value: token));
        }
      };

      subscriptions.add(
        installationIds.listen(
          fcm(LiveUpdatesTokenType.fcmInstallationId),
          onError: controller.addError,
        ),
      );
      if (registrationTokenRefresh != null) {
        subscriptions.add(
          registrationTokenRefresh.listen(
            fcm(LiveUpdatesTokenType.fcmRegistrationToken),
            onError: controller.addError,
          ),
        );
      }
      initialRegistrationToken?.call().then(
        fcm(LiveUpdatesTokenType.fcmRegistrationToken),
        onError: controller.addError,
      );
      subscriptions
        ..add(
          LiveUpdates.pushToStartTokens.listen(
            (t) => emit(
              LiveUpdatesToken(
                type: LiveUpdatesTokenType.pushToStart,
                value: t.hex,
              ),
            ),
            onError: controller.addError,
          ),
        )
        ..add(
          LiveUpdates.onStarted.listen(watch, onError: controller.addError),
        );
      LiveUpdates.active().then(
        (updates) => updates.forEach(watch),
        onError: controller.addError,
      );
    },
    onCancel: () async {
      final pending = List.of(subscriptions);
      subscriptions.clear();
      watchedUpdates.clear();
      seen.clear();
      await Future.wait(pending.map((s) => s.cancel()));
    },
  );
  return controller.stream;
}
