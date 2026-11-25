/// String formats shared with the native bridges.
library;

import 'dart:convert';

/// `"<update id>\n<action id>"`: a button press.
String encodePress(String updateId, String actionId) => '$updateId\n$actionId';

/// The press in [s], or `null` when it is malformed.
(String, String)? parsePress(String s) {
  final at = s.indexOf('\n');
  if (at <= 0) return null;
  return (s.substring(0, at), s.substring(at + 1));
}

/// `"<state>:<update id>"`: a lifecycle event, returned as `(id, state)`.
/// The state never contains `:`, so ids may.
(String, String)? parseEvent(String s) {
  final at = s.indexOf(':');
  if (at <= 0) return null;
  return (s.substring(at + 1), s.substring(0, at));
}

/// Seconds for the native `end`: -1 keeps the final content (system default
/// policy on iOS), 0 removes it now.
double dismissSeconds(Duration? dismissAfter) =>
    dismissAfter == null ? -1 : dismissAfter.inMilliseconds / 1000;

/// Schedules from the native bridges: a JSON array of `{"key": String,
/// "at": seconds since 1970}`. Malformed entries are skipped.
List<(String, DateTime)> parseSchedules(String json) {
  final Object? list;
  try {
    list = jsonDecode(json);
  } on FormatException {
    return const [];
  }
  if (list is! List) return const [];
  return [
    for (final e in list)
      if (e case {'key': final String key, 'at': final num at})
        (key, DateTime.fromMillisecondsSinceEpoch((at * 1000).round())),
  ];
}
