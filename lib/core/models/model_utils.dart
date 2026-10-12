import 'dart:convert';

/// Sentinel used by `copyWith` methods so that nullable fields can be
/// explicitly set to null (pass `null`) or left untouched (omit the argument).
const Object kUnset = Object();

/// Formats an instant as UTC ISO-8601.
String formatUtc(DateTime value) => value.toUtc().toIso8601String();

/// Parses a UTC ISO-8601 string (any offset is converted to UTC).
DateTime parseUtc(Object? value) {
  if (value is String) {
    return DateTime.parse(value).toUtc();
  }
  throw FormatException('Expected an ISO-8601 string but got: $value');
}

/// Like [parseUtc] but returns null for null.
DateTime? parseUtcOrNull(Object? value) {
  if (value == null) {
    return null;
  }
  return parseUtc(value);
}

String _two(int n) => n < 10 ? '0$n' : '$n';

/// Calendar date as `yyyy-MM-dd` (no time zone involved).
String formatDateOnly(DateTime value) {
  final String y = value.year.toString().padLeft(4, '0');
  return '$y-${_two(value.month)}-${_two(value.day)}';
}

/// Parses `yyyy-MM-dd` (or any ISO string, whose UTC calendar date is used)
/// into `DateTime.utc(y, m, d)`.
DateTime? parseDateOnly(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw FormatException('Expected a date string but got: $value');
  }
  final DateTime parsed = DateTime.parse(value);
  if (value.length <= 10) {
    return DateTime.utc(parsed.year, parsed.month, parsed.day);
  }
  final DateTime utc = parsed.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}

/// Element-wise list equality.
bool listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

/// Casts a decoded JSON object to `Map<String, Object?>`.
Map<String, Object?> asStringMap(Object? value) {
  if (value is Map) {
    return value.cast<String, Object?>();
  }
  throw FormatException('Expected a JSON object but got: $value');
}

/// Casts a decoded JSON array to a list of objects (empty for null).
List<Object?> asList(Object? value) {
  if (value == null) {
    return const <Object?>[];
  }
  if (value is List) {
    return value.cast<Object?>();
  }
  throw FormatException('Expected a JSON array but got: $value');
}

Object? _canonical(Object? value) {
  if (value is Map) {
    final List<String> keys = value.keys.map((Object? k) => k.toString()).toList()
      ..sort();
    return <String, Object?>{
      for (final String k in keys) k: _canonical(value[k]),
    };
  }
  if (value is List) {
    return value.map<Object?>(_canonical).toList();
  }
  return value;
}

/// JSON text with map keys sorted recursively, so two equal documents always
/// produce identical strings regardless of key order.
String canonicalJson(Object? value) => jsonEncode(_canonical(value));
