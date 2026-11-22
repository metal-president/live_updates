import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_updates/live_updates.dart';
import 'package:live_updates/src/image_store.dart';

/// A canned response for one URL.
class _Reply {
  const _Reply(this.status, {this.location, this.body = const [], this.length});

  final int status;
  final String? location;
  final List<int> body;
  final int? length;
}

class _FakeClient implements HttpClient {
  _FakeClient(this.replies);

  final Map<String, _Reply> replies;
  final requested = <Uri>[];

  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requested.add(url);
    return _FakeRequest(replies[url.toString()] ?? const _Reply(404));
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRequest implements HttpClientRequest {
  _FakeRequest(this.reply);

  final _Reply reply;

  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 5;

  @override
  Future<HttpClientResponse> close() async => _FakeResponse(reply);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  _FakeResponse(this.reply);

  final _Reply reply;

  @override
  int get statusCode => reply.status;

  @override
  bool get isRedirect => reply.status >= 300 && reply.status < 400;

  @override
  int get contentLength => reply.length ?? reply.body.length;

  @override
  HttpHeaders get headers => _FakeHeaders(reply.location);

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.fromIterable([if (reply.body.isNotEmpty) reply.body]).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHeaders implements HttpHeaders {
  _FakeHeaders(this.location);

  final String? location;

  @override
  String? value(String name) =>
      name == HttpHeaders.locationHeader ? location : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory dir;
  late ImageStore store;
  final png = File('example/assets/parcel.png').readAsBytesSync();

  setUp(() {
    dir = Directory.systemTemp.createTempSync('lu_download');
    store = ImageStore(dir);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<String> download(_FakeClient client, String url) =>
      HttpOverrides.runZoned(
        () => store.store(LiveUpdateImage.network(Uri.parse(url))),
        createHttpClient: (_) => client,
      );

  Future<Object?> failure(_FakeClient client, String url) async {
    try {
      await download(client, url);
      return null;
    } on Object catch (e) {
      return e;
    }
  }

  testWidgets('downloads an https image', (tester) async {
    await tester.runAsync(() async {
      final client = _FakeClient({
        'https://cdn.test/a.png': _Reply(200, body: png),
      });
      expect(
        await download(client, 'https://cdn.test/a.png'),
        startsWith(ImageStore.prefix),
      );
    });
  });

  testWidgets('follows https redirects', (tester) async {
    await tester.runAsync(() async {
      final client = _FakeClient({
        'https://cdn.test/a.png': const _Reply(302, location: '/b.png'),
        'https://cdn.test/b.png': _Reply(200, body: png),
      });
      await download(client, 'https://cdn.test/a.png');
      expect(client.requested.map((u) => u.path), ['/a.png', '/b.png']);
    });
  });

  testWidgets('rejects a redirect to http', (tester) async {
    await tester.runAsync(() async {
      final client = _FakeClient({
        'https://cdn.test/a.png': const _Reply(
          301,
          location: 'http://cdn.test/a.png',
        ),
      });
      final e = await failure(client, 'https://cdn.test/a.png');
      expect(e, isA<LiveUpdateException>());
      expect(client.requested, hasLength(1)); // http was never fetched
    });
  });

  testWidgets('rejects more than three redirects', (tester) async {
    await tester.runAsync(() async {
      final client = _FakeClient({
        for (var i = 0; i < 5; i++)
          'https://cdn.test/$i': _Reply(302, location: '/${i + 1}'),
      });
      expect(
        await failure(client, 'https://cdn.test/0'),
        isA<LiveUpdateException>(),
      );
      expect(client.requested, hasLength(4));
    });
  });

  testWidgets('rejects error responses and oversized images', (tester) async {
    await tester.runAsync(() async {
      final client = _FakeClient({
        'https://cdn.test/missing': const _Reply(404),
        'https://cdn.test/big': const _Reply(
          200,
          length: ImageStore.maxDownloadBytes + 1,
        ),
        'https://cdn.test/streamed': _Reply(
          200,
          length: -1,
          body: List.filled(ImageStore.maxDownloadBytes + 1, 0),
        ),
      });
      for (final url in [
        'https://cdn.test/missing',
        'https://cdn.test/big',
        'https://cdn.test/streamed',
      ]) {
        final e = await failure(client, url);
        expect(e, isA<LiveUpdateException>(), reason: url);
      }
      expect(dir.listSync(), isEmpty); // nothing was written
    });
  });
}
