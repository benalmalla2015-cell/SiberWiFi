/// Saved MikroTik router connection profile.
/// Passwords are kept in secure storage only, never in plain prefs.
class MikrotikRouterConfig {
  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final String password;
  final bool useSsl;
  /// Server-side id of the matching mikrotik_routers row
  /// (null until the first successful platform sync).
  final int? remoteId;
  final DateTime createdAt;

  const MikrotikRouterConfig({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    this.useSsl = false,
    this.remoteId,
    required this.createdAt,
  });

  MikrotikRouterConfig copyWith({
    String? name,
    String? host,
    int? port,
    String? username,
    String? password,
    bool? useSsl,
    int? remoteId,
  }) {
    return MikrotikRouterConfig(
      id: id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      useSsl: useSsl ?? this.useSsl,
      remoteId: remoteId ?? this.remoteId,
      createdAt: createdAt,
    );
  }

  /// Value equality on the stable profile id — required so
  /// `routerSessionProvider` (a `.family`) reuses one connection even
  /// when the config object is rebuilt from a restored `extra` Map.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MikrotikRouterConfig && other.id == id);

  @override
  int get hashCode => id.hashCode;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'username': username,
        'password': password,
        'useSsl': useSsl,
        'remoteId': remoteId,
        'createdAt': createdAt.toIso8601String(),
      };

  factory MikrotikRouterConfig.fromJson(Map<String, dynamic> json) => MikrotikRouterConfig(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        host: json['host']?.toString() ?? '',
        port: (json['port'] as num?)?.toInt() ?? 8728,
        username: json['username']?.toString() ?? 'admin',
        password: json['password']?.toString() ?? '',
        useSsl: json['useSsl'] == true,
        remoteId: (json['remoteId'] as num?)?.toInt(),
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.now(),
      );
}

/// Resolves a [MikrotikRouterConfig] from a GoRouter `extra` payload.
///
/// In-process pushes hand us the object itself, but after OS state
/// restoration (or a hot restart) GoRouter returns the serialised
/// payload as a decoded `Map`. The users route may also wrap the
/// object as `{'router': …, 'tab': …}` — handle all three shapes so a
/// rebuilt route never hits a blind `as` cast.
MikrotikRouterConfig? mikrotikRouterFromExtra(Object? extra) {
  if (extra is MikrotikRouterConfig) return extra;
  if (extra is Map) {
    final m = Map<String, dynamic>.from(extra);
    if (m.containsKey('router')) {
      return mikrotikRouterFromExtra(m['router']);
    }
    try {
      return MikrotikRouterConfig.fromJson(m);
    } catch (_) {
      return null;
    }
  }
  return null;
}
