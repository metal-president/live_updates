import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_updates/live_updates_platform_interface.dart';
import 'package:live_updates_fcm/live_updates_fcm.dart';

class _RecordingPlatform extends NoopLiveUpdatesPlatform {
  final payloads = <Map<String, Object?>>[];

  @override
  Future<bool> handleRemotePayload(Map<String, Object?> data) async {
    payloads.add(data);
    return true;
  }
}

void main() {
  late _RecordingPlatform platform;
  setUp(() => LiveUpdatesPlatform.instance = platform = _RecordingPlatform());

  test('forwards live_updates messages', () async {
    const data = {
      'live_updates_event': 'update',
      'live_updates_id': 'order-1',
      'live_updates_content': '{"title":"On the way","progress":0.5}',
    };
    expect(
      await LiveUpdatesFcm.handleMessage(const RemoteMessage(data: data)),
      isTrue,
    );
    expect(platform.payloads, [data]);
  });

  test('ignores other messages', () async {
    expect(await LiveUpdatesFcm.handleData({'chat': 'hi'}), isFalse);
    expect(platform.payloads, isEmpty);
  });
}
