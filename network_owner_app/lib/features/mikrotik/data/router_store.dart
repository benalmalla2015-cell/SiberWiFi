import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'router_model.dart';

/// Persists router connection profiles in the device secure enclave
/// (Android Keystore / iOS Keychain) via flutter_secure_storage.
class RouterStore {
  static const _key = 'mikrotik_routers_v1';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static Future<List<MikrotikRouterConfig>> load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => MikrotikRouterConfig.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveAll(List<MikrotikRouterConfig> routers) async {
    final raw = jsonEncode(routers.map((r) => r.toJson()).toList());
    await _storage.write(key: _key, value: raw);
  }

  static Future<void> upsert(MikrotikRouterConfig router) async {
    final routers = await load();
    final i = routers.indexWhere((r) => r.id == router.id);
    if (i >= 0) {
      routers[i] = router;
    } else {
      routers.add(router);
    }
    await saveAll(routers);
  }

  static Future<void> delete(String id) async {
    final routers = await load();
    routers.removeWhere((r) => r.id == id);
    await saveAll(routers);
  }
}
