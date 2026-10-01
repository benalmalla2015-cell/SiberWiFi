List<Map<String, dynamic>> toMapList(dynamic value) {
  if (value == null) return [];
  if (value is List) {
    return value
        .where((e) => e is Map)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }
  return [];
}

Map<String, dynamic> toMap(dynamic value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return {};
}
