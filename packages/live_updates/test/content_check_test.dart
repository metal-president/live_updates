import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:live_updates/live_updates.dart';
import 'package:live_updates/src/content_check.dart'
    show estimatedIosPayloadBytes, iosPayloadLimit;

List<LiveUpdateIssueCode> _codes(LiveUpdateContent c, {bool remote = false}) =>
    [for (final i in c.check(remote: remote)) i.code];

LiveUpdateIssue _only(LiveUpdateContent c, LiveUpdateIssueCode code) =>
    c.check().singleWhere((i) => i.code == code);

final _soon = DateTime.now().add(const Duration(hours: 1));

void main() {
  const ios = {TargetPlatform.iOS};
  const android = {TargetPlatform.android};
  const both = {TargetPlatform.iOS, TargetPlatform.android};

  test('plain content has no issues', () {
    expect(const LiveUpdateContent(title: 'Order').check(), isEmpty);
    expect(
      LiveUpdateContent(
        title: 'Order #1234',
        body: 'On the way',
        progress: .5,
        timer: LiveUpdateTimer.countdown(_soon),
        metrics: const [LiveUpdateMetric.integer('Stops', 2)],
        criticalMetric: 0,
        steps: const LiveUpdateSteps(['A', 'B', 'C'], current: 2),
        journey: const LiveUpdateJourney(from: 'Shop', to: 'Home'),
        endAt: _soon,
        endedContent: const LiveUpdateEndedContent(title: 'Delivered'),
        ios: const IosLiveUpdateOptions(
          layout: IosLiveUpdateLayout.stepper,
          compactTrailing: IosIslandContent.timer,
        ),
      ).check(remote: true),
      isEmpty,
    );
  });

  group('iOS layout data', () {
    for (final (layout, needs) in [
      (IosLiveUpdateLayout.timer, 'timer'),
      (IosLiveUpdateLayout.metrics, 'metrics'),
      (IosLiveUpdateLayout.stepper, 'steps'),
      (IosLiveUpdateLayout.journey, 'journey'),
    ]) {
      test('${layout.value} without $needs falls back to standard', () {
        final issue = _only(
          LiveUpdateContent(
            title: 'T',
            ios: IosLiveUpdateOptions(layout: layout),
          ),
          LiveUpdateIssueCode.layoutDataMissing,
        );
        expect(issue.platforms, ios);
        expect(issue.severity, LiveUpdateIssueSeverity.warning);
        expect(issue.message, contains(needs));
        expect(issue.message, contains('standard layout'));
      });
    }

    test('stepper with no labels falls back too', () {
      expect(
        _codes(
          const LiveUpdateContent(
            title: 'T',
            steps: LiveUpdateSteps([], current: 0),
            ios: IosLiveUpdateOptions(layout: IosLiveUpdateLayout.stepper),
          ),
        ),
        [LiveUpdateIssueCode.layoutDataMissing],
      );
    });

    test('standard and custom layouts need no data', () {
      for (final layout in [
        IosLiveUpdateLayout.standard,
        const IosLiveUpdateLayout.custom('delivery'),
      ]) {
        expect(
          LiveUpdateContent(
            title: 'T',
            ios: IosLiveUpdateOptions(layout: layout),
          ).check(),
          isEmpty,
        );
      }
    });
  });

  test('Dynamic Island choices without data show their fallback', () {
    final issues = const LiveUpdateContent(
      title: 'T',
      extra: {'gate': 'B12'},
      ios: IosLiveUpdateOptions(
        compactLeading: IosIslandContent.extra('seat'),
        compactTrailing: IosIslandContent.progress,
        minimal: IosIslandContent.timer,
      ),
    ).check();
    expect(issues.map((i) => i.code).toSet(), {
      LiveUpdateIssueCode.islandContentMissing,
    });
    expect(issues, hasLength(3));
    expect(issues.every((i) => i.platforms.length == 1), isTrue);
    expect(issues[0].message, contains('"seat"'));
    // Present data is fine, also from the deprecated iOS extra.
    expect(
      const LiveUpdateContent(
        title: 'T',
        body: 'B',
        ios: IosLiveUpdateOptions(
          // ignore: deprecated_member_use
          extra: {'seat': '12A'},
          compactLeading: IosIslandContent.extra('seat'),
          compactTrailing: IosIslandContent.body,
          minimal: IosIslandContent.icon,
        ),
      ).check(),
      isEmpty,
    );
  });

  test('metrics beyond three and an unused critical metric', () {
    final metrics = [
      for (var i = 0; i < 5; i++) LiveUpdateMetric.integer('M$i', i),
    ];
    final content = LiveUpdateContent(
      title: 'T',
      metrics: metrics,
      criticalMetric: 3,
    );
    expect(_codes(content), [
      LiveUpdateIssueCode.tooManyMetrics,
      LiveUpdateIssueCode.criticalMetricOutOfRange,
    ]);
    expect(_only(content, LiveUpdateIssueCode.tooManyMetrics).platforms, both);
    expect(
      _only(content, LiveUpdateIssueCode.criticalMetricOutOfRange).platforms,
      android,
    );
    expect(
      LiveUpdateContent(
        title: 'T',
        metrics: metrics.take(2).toList(),
        criticalMetric: 2,
      ).check().single.code,
      LiveUpdateIssueCode.criticalMetricOutOfRange,
    );
    // Without metrics there is nothing to point at (and nothing shown).
    expect(
      const LiveUpdateContent(title: 'T', criticalMetric: 4).check(),
      isEmpty,
    );
  });

  test('steps: current out of range, empty labels, too many stages', () {
    final issue = _only(
      const LiveUpdateContent(
        title: 'T',
        steps: LiveUpdateSteps(['A', 'B'], current: 2),
      ),
      LiveUpdateIssueCode.stepsCurrentOutOfRange,
    );
    expect(issue.platforms, both);
    expect(issue.message, contains('last stage'));
    expect(
      _only(
        const LiveUpdateContent(
          title: 'T',
          steps: LiveUpdateSteps(['A', ' ', ''], current: 0),
        ),
        LiveUpdateIssueCode.emptyStepLabel,
      ).message,
      contains('1, 2 are empty'),
    );
    final many = LiveUpdateSteps([
      for (var i = 0; i < 22; i++) 'S$i',
    ], current: 0);
    expect(_codes(LiveUpdateContent(title: 'T', steps: many)), [
      LiveUpdateIssueCode.tooManySteps,
    ]);
    // classic and own segments do not draw segments from steps.
    for (final options in [
      const AndroidLiveUpdateOptions(mode: AndroidLiveUpdateMode.classic),
      const AndroidLiveUpdateOptions(
        progressSegments: [AndroidProgressSegment(1)],
      ),
    ]) {
      expect(
        LiveUpdateContent(title: 'T', steps: many, android: options).check(),
        isEmpty,
      );
    }
    expect(
      LiveUpdateContent(
        title: 'T',
        steps: LiveUpdateSteps([
          for (var i = 0; i < 21; i++) 'S$i',
        ], current: 20),
      ).check(),
      isEmpty,
    );
  });

  test('an empty title is reported for Android promotion only', () {
    final issue = _only(
      const LiveUpdateContent(title: ''),
      LiveUpdateIssueCode.untitledLiveUpdate,
    );
    expect(issue.platforms, android);
    expect(
      const LiveUpdateContent(
        title: '',
        android: AndroidLiveUpdateOptions(mode: AndroidLiveUpdateMode.ongoing),
      ).check(),
      isEmpty,
    );
  });

  test('custom layouts: never promoted, names and keys', () {
    final content = const LiveUpdateContent(
      title: 'T',
      extra: {'Bad Key': 'x', 'image_x': 'y', 'ok': 'z'},
      android: AndroidLiveUpdateOptions(
        customLayout: AndroidCustomLayout('Courier.xml'),
      ),
    );
    expect(_codes(content), [
      LiveUpdateIssueCode.customLayoutNotPromoted,
      LiveUpdateIssueCode.invalidCustomLayoutName,
      LiveUpdateIssueCode.extraKeyNotShown,
      LiveUpdateIssueCode.extraKeyNotShown,
    ]);
    expect(
      content.check().every((i) => i.platforms.length == 1),
      isTrue,
      reason: 'Android only',
    );
    expect(
      const LiveUpdateContent(
        title: 'T',
        extra: {'Bad Key': 'x'},
        android: AndroidLiveUpdateOptions(
          mode: AndroidLiveUpdateMode.ongoing,
          customLayout: AndroidCustomLayout('live_update_courier'),
        ),
      ).check().map((i) => i.code),
      [LiveUpdateIssueCode.extraKeyNotShown],
    );
    // Without a custom layout, extra keys go to iOS only.
    expect(
      const LiveUpdateContent(title: 'T', extra: {'Bad Key': 'x'}).check(),
      isEmpty,
    );
  });

  test('icons the platform cannot find', () {
    final issues = const LiveUpdateContent(
      title: 'T',
      icon: LiveUpdateIcon.symbol('shippingbox'),
      ios: IosLiveUpdateOptions(islandIcon: LiveUpdateIcon.native('a/b')),
    ).check();
    expect(issues.map((i) => (i.code, i.platforms)), [
      (LiveUpdateIssueCode.symbolIconOnAndroid, android),
      (LiveUpdateIssueCode.invalidIconName, ios),
    ]);
  });

  test('buttons and chip text that Android cuts', () {
    final content = LiveUpdateContent(
      title: 'T',
      actions: [
        for (var i = 0; i < 4; i++) LiveUpdateAction(id: '$i', title: '$i'),
      ],
      android: const AndroidLiveUpdateOptions(shortCriticalText: '12 min.'),
    );
    expect(_codes(content), [
      LiveUpdateIssueCode.tooManyActions,
      LiveUpdateIssueCode.shortCriticalTextTooLong,
    ]);
    // Six characters fit; text of content that is not promoted is not shown.
    expect(
      const LiveUpdateContent(
        title: 'T',
        android: AndroidLiveUpdateOptions(shortCriticalText: '12 min'),
      ).check(),
      isEmpty,
    );
    expect(
      const LiveUpdateContent(
        title: 'T',
        android: AndroidLiveUpdateOptions(
          shortCriticalText: '12 minutes',
          mode: AndroidLiveUpdateMode.ongoing,
        ),
      ).check(),
      isEmpty,
    );
  });

  test('ended content that is never shown', () {
    const ended = LiveUpdateEndedContent(title: 'Delivered');
    expect(
      const LiveUpdateContent(
        title: 'T',
        endedContent: ended,
      ).check().map((i) => (i.code, i.platforms)),
      [
        (LiveUpdateIssueCode.endedContentNeverShown, ios),
        (LiveUpdateIssueCode.endedContentNeverShown, android),
      ],
    );
    // The iOS stale date shows it on iOS only.
    expect(
      LiveUpdateContent(
        title: 'T',
        endedContent: ended,
        ios: IosLiveUpdateOptions(staleDate: DateTime(2030)),
      ).check().map((i) => i.platforms),
      [android],
    );
    expect(
      LiveUpdateContent(
        title: 'T',
        endAt: DateTime(2030),
        endedContent: ended,
        android: const AndroidLiveUpdateOptions(removeAtEnd: true),
      ).check().single.message,
      contains('removeAtEnd'),
    );
  });

  test('Android removes the update before endAt', () {
    const ended = LiveUpdateEndedContent(title: 'Delivered');
    final eta = DateTime.now().add(const Duration(minutes: 30));
    // The countdown ends first, and Android removes the notification there.
    final countdown = LiveUpdateContent(
      title: 'T',
      timer: LiveUpdateTimer.countdown(eta),
      endAt: eta.add(const Duration(minutes: 5)),
      endedContent: ended,
    );
    expect(countdown.check().map((i) => (i.code, i.platforms)), [
      (LiveUpdateIssueCode.endedContentNeverShown, android),
    ]);
    expect(countdown.check().single.message, contains('countdown'));
    // endAt at the countdown end, or a countdown that is kept, is fine.
    expect(
      LiveUpdateContent(
        title: 'T',
        timer: LiveUpdateTimer.countdown(eta),
        endAt: eta,
        endedContent: ended,
      ).check(),
      isEmpty,
    );
    expect(
      countdown
          .copyWith(
            android: const AndroidLiveUpdateOptions(
              removeAtCountdownEnd: false,
            ),
          )
          .check(),
      isEmpty,
    );
    // Beyond maxDuration (eight hours by default; null is no limit).
    final late = LiveUpdateContent(
      title: 'T',
      endAt: DateTime.now().add(const Duration(hours: 9)),
      endedContent: ended,
    );
    expect(late.check().single.message, contains('maxDuration'));
    expect(
      late
          .copyWith(android: const AndroidLiveUpdateOptions(maxDuration: null))
          .check(),
      isEmpty,
    );
  });

  test('a countdown already over does not remove the update', () {
    expect(
      LiveUpdateContent(
        title: 'T',
        timer: LiveUpdateTimer.countdown(
          DateTime.now().subtract(const Duration(minutes: 1)),
        ),
        endAt: DateTime.now().add(const Duration(minutes: 5)),
        endedContent: const LiveUpdateEndedContent(title: 'Delivered'),
      ).check(),
      isEmpty,
    );
  });

  test('the ended icon is checked like the shared one', () {
    final issues = LiveUpdateContent(
      title: 'T',
      endAt: DateTime.now().add(const Duration(minutes: 5)),
      endedContent: const LiveUpdateEndedContent(
        title: 'Delivered',
        icon: LiveUpdateIcon.symbol('checkmark.circle.fill'),
      ),
    ).check();
    expect(issues.map((i) => (i.code, i.platforms)), [
      (LiveUpdateIssueCode.symbolIconOnAndroid, android),
    ]);
    expect(
      LiveUpdateContent(
        title: 'T',
        endAt: DateTime.now().add(const Duration(minutes: 5)),
        endedContent: const LiveUpdateEndedContent(
          title: 'Delivered',
          icon: LiveUpdateIcon.native('a/b'),
        ),
        android: const AndroidLiveUpdateOptions(
          smallIcon: LiveUpdateIcon.native('ic_stat'),
        ),
      ).check().map((i) => (i.code, i.platforms)),
      [(LiveUpdateIssueCode.invalidIconName, ios)],
    );
  });

  test('deprecated iOS pictures are iOS only', () {
    final issues = const LiveUpdateContent(
      title: 'T',
      ios: IosLiveUpdateOptions(
        // ignore: deprecated_member_use
        extraImages: {'map': LiveUpdateImage.asset('m.png')},
      ),
      android: AndroidLiveUpdateOptions(
        mode: AndroidLiveUpdateMode.ongoing,
        customLayout: AndroidCustomLayout('live_update_x'),
      ),
    ).check(remote: true);
    expect(issues.map((i) => (i.code, i.platforms)), [
      (LiveUpdateIssueCode.remoteImages, ios),
    ]);
  });

  group('iOS size', () {
    test('content over the ActivityKit limit is an error', () {
      final content = LiveUpdateContent(
        title: 'T',
        extra: {for (var i = 0; i < 50; i++) 'key$i': 'x' * 80},
      );
      expect(estimatedIosPayloadBytes(content), greaterThan(iosPayloadLimit));
      final issue = _only(content, LiveUpdateIssueCode.payloadTooLarge);
      expect(issue.severity, LiveUpdateIssueSeverity.error);
      expect(issue.platforms, ios);
    });

    test('the estimate counts what ActivityKit stores', () {
      const plain = LiveUpdateContent(title: 'T');
      final base = estimatedIosPayloadBytes(plain);
      // Empty collections are encoded too.
      expect(
        base,
        '{"title":"T","actions":[],"extra":{},"extraImages":{},'
                '"metrics":[]}'
            .length,
      );
      // Android options are not part of the content state.
      expect(
        estimatedIosPayloadBytes(
          const LiveUpdateContent(
            title: 'T',
            android: AndroidLiveUpdateOptions(
              shortCriticalText: 'a long text that iOS never sees',
            ),
          ),
        ),
        base,
      );
      // A picture becomes a stored file name, not its bytes.
      expect(
        estimatedIosPayloadBytes(
          const LiveUpdateContent(
            title: 'T',
            image: LiveUpdateImage.asset('assets/a/very/long/name.png'),
          ),
        ),
        base + '"image":"lu_${'0' * 32}.png",'.length,
      );
      // Buttons encode both flags, and "/" is written as "\\/".
      expect(
        estimatedIosPayloadBytes(
          const LiveUpdateContent(
            title: 'T',
            route: '/a',
            actions: [LiveUpdateAction(id: 'x', title: 'X')],
          ),
        ),
        base +
            '"route":"\\/a",'.length +
            '{"id":"x","title":"X","opensApp":false,"requiresUnlock":false}'
                .length,
      );
      // Multi-byte text counts in UTF-8 bytes.
      expect(
        estimatedIosPayloadBytes(const LiveUpdateContent(title: 'ü')),
        base + 1,
      );
    });
  });

  test('remote content: pictures, layout names and asset icons', () {
    const content = LiveUpdateContent(
      title: 'T',
      image: LiveUpdateImage.asset('a.png'),
      icon: LiveUpdateIcon.asset('assets/icon.png'),
      android: AndroidLiveUpdateOptions(
        mode: AndroidLiveUpdateMode.ongoing,
        customLayout: AndroidCustomLayout(
          'courier',
          expanded: 'live_update_courier_expanded',
        ),
      ),
    );
    expect(content.check(), isEmpty);
    final issues = content.check(remote: true);
    expect(issues.map((i) => (i.code, i.platforms)), [
      (LiveUpdateIssueCode.remoteImages, both),
      (LiveUpdateIssueCode.remoteLayoutName, android),
      (LiveUpdateIssueCode.remoteAssetIcon, ios),
    ]);
    expect(issues[1].message, contains('"courier"'));
    expect(issues[1].message, contains('system template'));
    expect(
      const LiveUpdateContent(
        title: 'T',
        android: AndroidLiveUpdateOptions(
          mode: AndroidLiveUpdateMode.ongoing,
          customLayout: AndroidCustomLayout(
            'live_update_courier',
            expanded: 'courier_expanded',
          ),
        ),
      ).check(remote: true).single.message,
      contains('collapsed layout is used'),
    );
    expect(issues[2].message, contains('preloadIcons'));
  });

  test('issues print their severity, platforms and code', () {
    expect(
      _only(
        const LiveUpdateContent(title: ''),
        LiveUpdateIssueCode.untitledLiveUpdate,
      ).toString(),
      startsWith('warning [Android] untitledLiveUpdate: title is empty'),
    );
    expect(
      const LiveUpdateIssue(
        LiveUpdateIssueCode.tooManyMetrics,
        LiveUpdateIssueSeverity.info,
        both,
        'm',
      ),
      const LiveUpdateIssue(
        LiveUpdateIssueCode.tooManyMetrics,
        LiveUpdateIssueSeverity.info,
        {TargetPlatform.android, TargetPlatform.iOS},
        'm',
      ),
    );
  });
}
