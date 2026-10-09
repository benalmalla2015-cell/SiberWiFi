import 'dart:math';

import 'package:router_os_client/router_os_client.dart';

import 'router_model.dart';

/// Thin wrapper around RouterOSClient exposing the operations the
/// owner app needs. A single instance represents one live session —
/// create per screen, always call [close] when done.
class RouterOsService {
  RouterOsService._(this._client);

  final RouterOSClient _client;

  static const _timeout = Duration(seconds: 12);

  /// Opens a socket + logs in. Throws on failure.
  static Future<RouterOsService> connect(MikrotikRouterConfig cfg) async {
    final client = RouterOSClient(
      address: cfg.host,
      user: cfg.username,
      password: cfg.password,
      port: cfg.port,
      useSsl: cfg.useSsl,
      timeout: _timeout,
    );
    final ok = await client.login();
    if (!ok) {
      client.close();
      throw LoginError('فشل تسجيل الدخول — تحقق من بيانات الاعتماد');
    }
    return RouterOsService._(client);
  }

  /// Test connectivity + credentials. Returns router identity name.
  static Future<String> testConnection(MikrotikRouterConfig cfg) async {
    final svc = await connect(cfg);
    try {
      final res = await svc._client.talk(['/system/identity/print']);
      return res.isNotEmpty
          ? (res.first['name'] ?? 'RouterOS')
          : 'RouterOS';
    } finally {
      svc.close();
    }
  }

  void close() => _client.close();

  // ── System info ────────────────────────────────────────────────

  Future<Map<String, String>> systemResource() async {
    final res = await _client.talk(['/system/resource/print']);
    return res.isNotEmpty ? res.first : {};
  }

  Future<String> identity() async {
    final res = await _client.talk(['/system/identity/print']);
    return res.isNotEmpty ? (res.first['name'] ?? '') : '';
  }

  Future<List<Map<String, String>>> interfaces() =>
      _client.talk(['/interface/print']);

  // ── Hotspot ────────────────────────────────────────────────────

  Future<List<Map<String, String>>> hotspotUsers() =>
      _client.talk(['/ip/hotspot/user/print']);

  Future<List<Map<String, String>>> hotspotActive() =>
      _client.talk(['/ip/hotspot/active/print']);

  Future<List<Map<String, String>>> hotspotProfiles() =>
      _client.talk(['/ip/hotspot/user/profile/print']);

  /// Creates one hotspot user (a voucher code) on the router.
  Future<void> addHotspotUser({
    required String name,
    String? password,
    String? profile,
    String? comment,
    String? limitUptime,
  }) async {
    final params = <String, String>{'name': name};
    if (password != null && password.isNotEmpty) {
      params['password'] = password;
    }
    if (profile != null && profile.isNotEmpty) params['profile'] = profile;
    if (comment != null && comment.isNotEmpty) params['comment'] = comment;
    if (limitUptime != null && limitUptime.isNotEmpty) {
      params['limit-uptime'] = limitUptime;
    }
    await _client.talk(['/ip/hotspot/user/add'], params);
  }

  Future<void> removeHotspotUser(String id) =>
      _client.talk(['/ip/hotspot/user/remove'], {'numbers': id});
}

/// Generates random voucher codes (uppercase letters + digits,
/// ambiguous chars excluded for readability when printed).
class VoucherGenerator {
  static const _chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static final _rand = Random.secure();

  static String code({int length = 8}) =>
      List.generate(length, (_) => _chars[_rand.nextInt(_chars.length)])
          .join();
}
