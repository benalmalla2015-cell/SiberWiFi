/// Hotspot user lifecycle classification — mirrors the status chips
/// used by mature MikroTik managers (الكل/نشط/غير نشط/منتهي/معطّل).
enum HotspotUserStatus { active, idle, expired, disabled }

extension HotspotUserStatusX on HotspotUserStatus {
  String get label => switch (this) {
        HotspotUserStatus.active => 'متصل',
        HotspotUserStatus.idle => 'غير نشط',
        HotspotUserStatus.expired => 'منتهي',
        HotspotUserStatus.disabled => 'معطّل',
      };
}

/// Parses RouterOS duration syntax into seconds.
/// Handles: "1w2d3h4m5s", "2h15m", "35m", "45s", "1d", "" → 0.
int rosDurationToSeconds(String? raw) {
  if (raw == null || raw.isEmpty) return 0;
  var total = 0;
  final re = RegExp(r'(\d+)([wdhms])');
  for (final m in re.allMatches(raw)) {
    final v = int.parse(m.group(1)!);
    total += switch (m.group(2)) {
      'w' => v * 604800,
      'd' => v * 86400,
      'h' => v * 3600,
      'm' => v * 60,
      's' => v,
      _ => 0,
    };
  }
  return total;
}

/// Classifies a hotspot user row (as returned by /ip/hotspot/user/print)
/// against the set of currently-connected usernames.
HotspotUserStatus classifyHotspotUser(
  Map<String, String> user,
  Set<String> activeNames,
) {
  if (user['disabled'] == 'true') return HotspotUserStatus.disabled;
  final limit = rosDurationToSeconds(user['limit-uptime']);
  final used = rosDurationToSeconds(user['uptime']);
  if (limit > 0 && used >= limit) return HotspotUserStatus.expired;
  if (activeNames.contains(user['name'])) return HotspotUserStatus.active;
  return HotspotUserStatus.idle;
}

/// Human-readable total usage "12.4 MB" for a user row.
String hotspotUsageLabel(Map<String, String> user) {
  int b(String k) => int.tryParse(user[k] ?? '') ?? 0;
  final total = b('bytes-in') + b('bytes-out');
  if (total <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = total.toDouble();
  var u = 0;
  while (v >= 1024 && u < units.length - 1) {
    v /= 1024;
    u++;
  }
  return '${v.toStringAsFixed(v >= 100 ? 0 : 1)} ${units[u]}';
}
