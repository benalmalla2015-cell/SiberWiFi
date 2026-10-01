/// Parses a date-time string coming from the backend (stored/returned in UTC,
/// e.g. "2026-08-07 10:15:30" with no timezone marker) and converts it to the
/// device's local time.
///
/// `DateTime.tryParse` treats a string with no timezone marker as already
/// being in local time, which produces the wrong wall-clock time when the
/// backend actually sends UTC timestamps. This helper normalizes the string
/// to be explicitly UTC before converting it to local time.
DateTime? parseUtcToLocal(dynamic raw) {
  if (raw == null) return null;
  var value = raw.toString().trim();
  if (value.isEmpty) return null;
  value = value.contains('T') ? value : value.replaceFirst(' ', 'T');
  if (!value.endsWith('Z') && !RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(value)) {
    value = '${value}Z';
  }
  return DateTime.tryParse(value)?.toLocal();
}
