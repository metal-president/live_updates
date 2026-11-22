// Sends test pushes for live_updates. Uses only dart:io plus the `openssl`
// and `curl` command line tools (APNs requires HTTP/2, which dart:io lacks).
//
// APNs (iOS Live Activity, token-based auth with a .p8 key):
//   dart run tool/send_push.dart apns --team-id ABCDE12345 --key-id KEY123 \
//     --key AuthKey_KEY123.p8 --bundle-id com.example.app --sandbox \
//     --token <push or push-to-start token> --event start \
//     --content '{"title":"Order #1","body":"Preparing","progress":0.1,"route":"/orders/1"}'
//
// APNs broadcast (iOS 18; needs Broadcast Capability for the App ID):
//   dart run tool/send_push.dart apns-channel --action create --sandbox \
//     --team-id ... --key-id ... --key AuthKey.p8 --bundle-id com.example.app
//   (prints apns-channel-id; --store-latest keeps the latest message 8 h;
//    --action list, or --action delete --channel <id>)
//   dart run tool/send_push.dart apns-broadcast --sandbox ... --channel <id> \
//     --event update --content '{"title":"2 - 1","body":"78 min"}'
//   Start with LiveUpdates.start(content, iosChannelId: <id>) or with a
//   push-to-start that passes --input-push-channel <id>.
//
// FCM to Android (data message handled by live_updates_fcm):
//   dart run tool/send_push.dart fcm --service-account sa.json \
//     --fid <Firebase Installation ID> --event update --id order-1 \
//     --content '{"title":"Order #1","progress":0.5}'
//
// FCM to iOS Live Activity (FCM forwards to APNs):
//   dart run tool/send_push.dart fcm-ios --service-account sa.json \
//     --fid <Firebase Installation ID> --live-activity-token <hex> \
//     --event update --content '{"title":"Order #1","progress":0.5}'
//
// FCM targets: --fid <installation ID> (recommended) or --token <legacy token>.
// Common options: --event start|update|end, --dismiss-after <seconds> (end),
// --alert-title/--alert-body (APNs alert, required by Apple for start),
// --dry-run (print the request instead of sending).
// --activity-key <key> (start: sets the key that LiveUpdates.find() uses).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.first.startsWith('-')) {
    stderr.writeln(
      'Usage: send_push.dart '
      '<apns|apns-channel|apns-broadcast|fcm|fcm-ios> [options]',
    );
    exit(64);
  }
  final command = args.first;
  final o = _parse(args.skip(1).toList());
  final event = o['event'] ?? 'update';
  if (!const {'start', 'update', 'end'}.contains(event)) {
    _fail('--event must be start, update or end');
  }
  final content = jsonDecode(o['content'] ?? '{"title":"live_updates"}');
  final dryRun = o.containsKey('dry-run');

  switch (command) {
    case 'apns':
      final aps = _aps(event, content, o);
      final host = o.containsKey('sandbox')
          ? 'api.sandbox.push.apple.com'
          : 'api.push.apple.com';
      final jwt = _apnsJwtFrom(o);
      await _curl(
        url: 'https://$host/3/device/${_req(o, 'token')}',
        headers: {
          'authorization': 'bearer $jwt',
          'apns-push-type': 'liveactivity',
          'apns-topic': '${_req(o, 'bundle-id')}.push-type.liveactivity',
          'apns-priority': o['priority'] ?? '10',
        },
        body: {'aps': aps},
        http2: true,
        dryRun: dryRun,
      );
    case 'apns-channel':
      // Channel management (iOS 18 broadcast). --action create|list|delete.
      final bundle = _req(o, 'bundle-id');
      final host = o.containsKey('sandbox')
          ? 'api-manage-broadcast.sandbox.push.apple.com:2195'
          : 'api-manage-broadcast.push.apple.com:2196';
      final auth = {'authorization': 'bearer ${_apnsJwtFrom(o)}'};
      switch (o['action'] ?? 'create') {
        case 'create':
          // apns-channel-id in the response headers is the new channel.
          await _curl(
            url: 'https://$host/1/apps/$bundle/channels',
            headers: auth,
            body: {
              'message-storage-policy': o.containsKey('store-latest') ? 1 : 0,
              'push-type': 'LiveActivity',
            },
            http2: true,
            showHeaders: true,
            success: {201},
            dryRun: dryRun,
          );
        case 'list':
          await _curl(
            url: 'https://$host/1/apps/$bundle/all-channels',
            method: 'GET',
            headers: auth,
            http2: true,
            dryRun: dryRun,
          );
        case 'delete':
          await _curl(
            url: 'https://$host/1/apps/$bundle/channels',
            method: 'DELETE',
            headers: {...auth, 'apns-channel-id': _req(o, 'channel')},
            http2: true,
            success: {204},
            dryRun: dryRun,
          );
        default:
          _fail('--action must be create, list or delete');
      }
    case 'apns-broadcast':
      // iOS 18 broadcast to every activity on a channel (update or end only).
      if (event == 'start') _fail('Broadcasts cannot start Live Activities');
      final host = o.containsKey('sandbox')
          ? 'api.sandbox.push.apple.com'
          : 'api.push.apple.com';
      await _curl(
        url: 'https://$host/4/broadcasts/apps/${_req(o, 'bundle-id')}',
        headers: {
          'authorization': 'bearer ${_apnsJwtFrom(o)}',
          'apns-channel-id': _req(o, 'channel'),
          'apns-push-type': 'liveactivity',
          'apns-priority': o['priority'] ?? '10',
          // 0: deliver once, do not store (required for no-storage channels).
          'apns-expiration': o['expiration'] ?? '0',
        },
        body: {'aps': _aps(event, content, o)},
        http2: true,
        dryRun: dryRun,
      );
    case 'fcm':
      final message = {
        ..._fcmTarget(o),
        'android': {'priority': 'high'},
        'data': {
          'live_updates_event': event,
          'live_updates_id': _req(o, 'id'),
          // An end without --content just removes the notification.
          if (event != 'end' || o.containsKey('content'))
            'live_updates_content': jsonEncode(content),
          'live_updates_dismiss_after': ?o['dismiss-after'],
        },
      };
      await _sendFcm(o, message, dryRun);
    case 'fcm-ios':
      final message = {
        ..._fcmTarget(o),
        'apns': {
          'live_activity_token': _req(o, 'live-activity-token'),
          'headers': {'apns-priority': o['priority'] ?? '10'},
          'payload': {'aps': _aps(event, content, o)},
        },
      };
      await _sendFcm(o, message, dryRun);
    default:
      _fail('Unknown command $command');
  }
}

/// FCM send target: `--fid` (Firebase Installation ID, recommended) or
/// `--token` (legacy registration token).
Map<String, String> _fcmTarget(Map<String, String> o) => switch (o) {
  {'fid': _, 'token': _} => _fail('Pass either --fid or --token, not both'),
  {'fid': final fid} => {'fid': fid},
  {'token': final token} => {'token': token},
  _ => _fail('Missing --fid (or legacy --token)'),
};

/// The `aps` dictionary of a Live Activity push.
Map<String, Object?> _aps(
  String event,
  Object? content,
  Map<String, String> o,
) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return {
    'timestamp': now,
    'event': event,
    'content-state': content,
    if (event == 'start') ...{
      'attributes-type': 'LiveUpdatesAttributes',
      'attributes': <String, Object?>{'key': ?o['activity-key']},
      // iOS 18: the started activity listens to this broadcast channel.
      'input-push-channel': ?o['input-push-channel'],
    },
    if (o['alert-title'] != null || event == 'start')
      'alert': {
        'title': o['alert-title'] ?? 'Live update',
        'body': o['alert-body'] ?? '',
      },
    if (event == 'end') 'dismissal-date': now + _seconds(o, 'dismiss-after'),
    if (o.containsKey('stale-after'))
      'stale-date': now + _seconds(o, 'stale-after'),
  };
}

Future<void> _sendFcm(
  Map<String, String> o,
  Map<String, Object?> message,
  bool dryRun,
) async {
  final sa = jsonDecode(
    File(_req(o, 'service-account')).readAsStringSync(),
  ) as Map<String, Object?>;
  final project = sa['project_id'] as String;
  final token = dryRun ? '<oauth token>' : await _googleAccessToken(sa);
  await _curl(
    url: 'https://fcm.googleapis.com/v1/projects/$project/messages:send',
    headers: {'authorization': 'Bearer $token'},
    body: {'message': message},
    dryRun: dryRun,
  );
}

/// OAuth2 access token for the FCM scope from a service account key.
Future<String> _googleAccessToken(Map<String, Object?> sa) async {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final unsigned =
      '${_b64(utf8.encode(jsonEncode({'alg': 'RS256', 'typ': 'JWT'})))}.'
      '${_b64(utf8.encode(jsonEncode({'iss': sa['client_email'], 'scope': 'https://www.googleapis.com/auth/firebase.messaging', 'aud': 'https://oauth2.googleapis.com/token', 'iat': now, 'exp': now + 3600})))}';
  final signature = _opensslSign(unsigned, sa['private_key'] as String);
  final assertion = '$unsigned.${_b64(signature)}';
  final result = await _curlWithConfig([
    'url = ${_q('https://oauth2.googleapis.com/token')}',
    'data-raw = ${_q('grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=$assertion')}',
  ]);
  final json = jsonDecode(result.stdout as String) as Map<String, Object?>;
  final token = json['access_token'];
  if (token is! String) _fail('OAuth token request failed: ${result.stdout}');
  return token;
}

/// APNs JWT from --team-id, --key-id and --key.
String _apnsJwtFrom(Map<String, String> o) => _apnsJwt(
  _req(o, 'team-id'),
  _req(o, 'key-id'),
  File(_req(o, 'key')).readAsStringSync(),
);

/// ES256 JWT for APNs token-based authentication.
String _apnsJwt(String teamId, String keyId, String p8) {
  final unsigned =
      '${_b64(utf8.encode(jsonEncode({'alg': 'ES256', 'kid': keyId})))}.'
      '${_b64(utf8.encode(jsonEncode({'iss': teamId, 'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000})))}';
  final der = _opensslSign(unsigned, p8);
  return '$unsigned.${_b64(_derToJose(der))}';
}

/// Signs [data] with SHA-256 and the PEM [key] (EC or RSA) using openssl.
Uint8List _opensslSign(String data, String key) {
  final dir = Directory.systemTemp.createTempSync('live_updates_push');
  try {
    final keyFile = File('${dir.path}/key.pem')..writeAsStringSync(key);
    final dataFile = File('${dir.path}/data')..writeAsStringSync(data);
    final result = Process.runSync('openssl', [
      'dgst',
      '-sha256',
      '-sign',
      keyFile.path,
      dataFile.path,
    ], stdoutEncoding: null);
    if (result.exitCode != 0) {
      throw StateError('openssl failed: ${result.stderr}');
    }
    return Uint8List.fromList(result.stdout as List<int>);
  } finally {
    // Always remove the private key copy (exit() would skip this).
    dir.deleteSync(recursive: true);
  }
}

/// Converts a DER ECDSA signature into the 64-byte r||s form JWS expects.
Uint8List _derToJose(Uint8List der) {
  var i = 2; // SEQUENCE tag + length (signatures are < 128 bytes)
  Uint8List readInt() {
    if (der[i] != 0x02) _fail('Unexpected ECDSA signature encoding');
    final len = der[i + 1];
    var bytes = der.sublist(i + 2, i + 2 + len);
    i += 2 + len;
    while (bytes.length > 32 && bytes.first == 0) {
      bytes = bytes.sublist(1);
    }
    return Uint8List(32)..setRange(32 - bytes.length, 32, bytes);
  }

  return Uint8List.fromList([...readInt(), ...readInt()]);
}

Future<void> _curl({
  required String url,
  required Map<String, String> headers,
  Object? body,
  String method = 'POST',
  bool http2 = false,
  bool dryRun = false,
  bool showHeaders = false,
  Set<int> success = const {200},
}) async {
  if (dryRun) {
    stdout
      ..writeln('$method $url')
      ..writeln(
        headers.entries
            .map(
              (e) =>
                  '${e.key}: ${e.key == 'authorization' ? '<redacted>' : e.value}',
            )
            .join('\n'),
      );
    if (body != null) {
      stdout
        ..writeln()
        ..writeln(const JsonEncoder.withIndent('  ').convert(body));
    }
    return;
  }
  final result = await _curlWithConfig([
    'url = ${_q(url)}',
    'request = ${_q(method)}',
    'write-out = ${_q(r'\nHTTP %{http_code}\n')}',
    if (http2) 'http2',
    if (showHeaders) 'include',
    for (final h in headers.entries) 'header = ${_q('${h.key}: ${h.value}')}',
    if (body != null) ...[
      'header = ${_q('content-type: application/json')}',
      'data-raw = ${_q(jsonEncode(body))}',
    ],
  ]);
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  final code = RegExp(r'HTTP (\d{3})').allMatches(result.stdout as String);
  if (code.isEmpty || !success.contains(int.parse(code.last.group(1)!))) {
    exitCode = 1;
  }
}

/// Runs curl with its options read from stdin (`--config -`), so tokens and
/// keys never appear in the process list.
Future<ProcessResult> _curlWithConfig(List<String> lines) async {
  final process = await Process.start('curl', ['-sS', '--config', '-']);
  process.stdin.writeln(lines.join('\n'));
  await process.stdin.close();
  final out = process.stdout.transform(utf8.decoder).join();
  final err = process.stderr.transform(utf8.decoder).join();
  final code = await process.exitCode;
  return ProcessResult(process.pid, code, await out, await err);
}

/// Quotes a value for a curl config file. Line breaks are rejected so a
/// value can never start another config line.
String _q(String value) {
  if (value.contains('\n') || value.contains('\r')) {
    _fail('Values must not contain line breaks');
  }
  return '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
}

String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

Map<String, String> _parse(List<String> args) {
  final out = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (!a.startsWith('--')) _fail('Unexpected argument $a');
    final key = a.substring(2);
    if (i + 1 < args.length && !args[i + 1].startsWith('--')) {
      out[key] = args[++i];
    } else {
      out[key] = 'true';
    }
  }
  return out;
}

String _req(Map<String, String> o, String key) =>
    o[key] ?? _fail('Missing --$key');

Never _fail(String message) {
  stderr.writeln(message);
  exit(64);
}

/// Whole seconds from option [name] (0 when missing).
int _seconds(Map<String, String> o, String name) {
  final value = o[name];
  if (value == null) return 0;
  return int.tryParse(value) ?? _fail('--$name must be whole seconds');
}
