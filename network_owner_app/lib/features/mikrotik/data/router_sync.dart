import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import 'router_model.dart';
import 'router_store.dart';
import '../presentation/providers/mikrotik_provider.dart';

/// Syncs a locally-saved router profile to the platform's
/// `mikrotik_routers` registry after each successful connection —
/// keeps the server-side inventory (identity, board, user counts)
/// fresh so sales/audit views know which router produced which cards.
///
/// Fire-and-forget: a sync failure must never break the dashboard,
/// so callers swallow errors silently.
class RouterSyncService {
  RouterSyncService._();

  /// POST /network-owner/mikrotik/routers/sync — upserts by
  /// (host, port, username) and returns the server row id, which we
  /// store locally so card uploads can reference the router.
  static Future<int?> sync(Ref ref, MikrotikRouterConfig cfg,
      {RouterSnapshot? snap, int? networkId}) async {
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.post(
        '/network-owner/mikrotik/routers/sync',
        data: {
          'host': cfg.host,
          'api_port': cfg.port,
          'username': cfg.username,
          // api_password is intentionally NOT sent — the server only
          // needs the registry entry; credentials stay on-device.
          'name': cfg.name.isEmpty ? cfg.host : cfg.name,
          'identity': ?snap?.identity,
          'board_name': ?snap?.board,
          'os_version': ?snap?.version,
          'uptime': ?snap?.uptime,
          'hotspot_users_count': ?snap?.users.length,
          'hotspot_active_count': ?snap?.active.length,
          'network_id': ?networkId,
        },
      );
      final data = res.data;
      if (data is Map && data['success'] == true) {
        final id = (data['data']?['id'] as num?)?.toInt();
        if (id != null && id != cfg.remoteId) {
          await RouterStore.upsert(cfg.copyWith(remoteId: id));
        }
        return id;
      }
    } catch (_) {
      // Offline/server unreachable — sync is best-effort.
    }
    return null;
  }
}
