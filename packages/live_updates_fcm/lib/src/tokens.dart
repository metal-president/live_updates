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
/// Every listener gets its own subscriptions to the FCM token, iOS
/// push-to-start tokens and the push tokens of every live update that is
/// running or starts later. Token sources replay their current value to new
/// listeners, so subscribing late or again still yields the current tokens.
/// Each distinct token is emitted once per listener.
@internal
Stream<LiveUpdatesToken> mergeTokens({
  required Stream<String> installationIds,
  Future<String?> Function()? initialRegistrationToken,
  Stream<String>? registrationTokenRefresh,
}) => Stream<LiveUpdatesToken>.multi((listener) {
  var active = true;
  final subscriptions = <StreamSubscription<Object?>>[];
  final perUpdate = <String, List<StreamSubscription<Object?>>>{};
  final seen = <LiveUpdatesToken>{};

  void emit(LiveUpdatesToken token) {
    if (active && seen.add(token)) listener.add(token);
  }

  void error(Object e, StackTrace s) {
    if (active) listener.addError(e, s);
  }

  void stopWatching(String id) {
    for (final sub in perUpdate.remove(id) ?? const []) {
      unawaited(sub.cancel());
    }
  }

  void watch(LiveUpdate update) {
    if (!active || perUpdate.containsKey(update.id)) return;
    perUpdate[update.id] = [
      update.pushTokens.listen(
        (t) => emit(
          LiveUpdatesToken(
            type: LiveUpdatesTokenType.activity,
            value: t.hex,
            updateId: update.id,
          ),
        ),
        onError: error,
      ),
      // Ended updates cannot be pushed to any more: stop watching them.
      update.states.listen((state) {
        if (state == LiveUpdateState.ended ||
            state == LiveUpdateState.dismissed) {
          stopWatching(update.id);
        }
      }, onError: error),
    ];
  }

  void Function(String?) fcm(LiveUpdatesTokenType type) => (token) {
    if (token != null && token.isNotEmpty) {
      emit(LiveUpdatesToken(type: type, value: token));
    }
  };

  subscriptions.add(
    installationIds.listen(
      fcm(LiveUpdatesTokenType.fcmInstallationId),
      onError: error,
    ),
  );
  if (registrationTokenRefresh != null) {
    subscriptions.add(
      registrationTokenRefresh.listen(
        fcm(LiveUpdatesTokenType.fcmRegistrationToken),
        onError: error,
      ),
    );
  }
  initialRegistrationToken?.call().then(
    fcm(LiveUpdatesTokenType.fcmRegistrationToken),
    onError: error,
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
        onError: error,
      ),
    )
    ..add(LiveUpdates.onStarted.listen(watch, onError: error));
  LiveUpdates.active().then(
    (updates) => updates.forEach(watch),
    onError: error,
  );

  listener.onCancel = () async {
    // Late async results (getToken, active) are ignored from here on.
    active = false;
    final pending = [
      ...subscriptions,
      for (final subs in perUpdate.values) ...subs,
    ];
    subscriptions.clear();
    perUpdate.clear();
    await Future.wait(pending.map((s) => s.cancel()));
  };
});
