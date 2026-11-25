import 'package:flutter_test/flutter_test.dart';
import 'package:live_updates/src/platform/wire.dart';

void main() {
  test('presses round-trip and malformed ones are dropped', () {
    expect(parsePress(encodePress('order-1', 'cancel')), ('order-1', 'cancel'));
    expect(parsePress('id\naction\nwith newline'), (
      'id',
      'action\nwith newline',
    ));
    expect(parsePress('no separator'), isNull);
    expect(parsePress('\naction'), isNull);
  });

  test('events keep ids that contain a colon', () {
    expect(parseEvent('ended:order:1'), ('order:1', 'ended'));
    expect(parseEvent('started:A-B'), ('A-B', 'started'));
    expect(parseEvent('broken'), isNull);
  });

  test('dismiss times', () {
    expect(dismissSeconds(null), -1);
    expect(dismissSeconds(Duration.zero), 0);
    expect(dismissSeconds(const Duration(milliseconds: 1500)), 1.5);
  });

  test('schedules', () {
    expect(
      parseSchedules('[{"key":"a","at":1700000000.5},{"key":"b","at":1}]'),
      [
        ('a', DateTime.fromMillisecondsSinceEpoch(1700000000500)),
        ('b', DateTime.fromMillisecondsSinceEpoch(1000)),
      ],
    );
    // Malformed entries are skipped; malformed JSON gives nothing.
    expect(
      parseSchedules('[{"key":1,"at":2},{"at":3},"x",{"key":"c","at":4}]'),
      [('c', DateTime.fromMillisecondsSinceEpoch(4000))],
    );
    expect(parseSchedules('{'), isEmpty);
    expect(parseSchedules('{"key":"a"}'), isEmpty);
  });
}
