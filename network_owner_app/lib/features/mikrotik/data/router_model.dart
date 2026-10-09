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
  final DateTime createdAt;

  const MikrotikRouterConfig({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    this.useSsl = false,
    required this.createdAt,
  });

  MikrotikRouterConfig copyWith({
    String? name,
    String? host,
    int? port,
    String? username,
    String? password,
    bool? useSsl,
  }) {
    return MikrotikRouterConfig(
      id: id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      useSsl: useSsl ?? this.useSsl,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'username': username,
        'password': password,
        'useSsl': useSsl,
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
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.now(),
      );
}
