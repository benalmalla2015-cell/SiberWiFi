import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/router_model.dart';
import '../../data/router_os_service.dart';
import '../../data/router_store.dart';

/// Saved router profiles (loaded from secure storage).
final routersProvider =
    AsyncNotifierProvider<RoutersNotifier, List<MikrotikRouterConfig>>(
  RoutersNotifier.new,
);

class RoutersNotifier extends AsyncNotifier<List<MikrotikRouterConfig>> {
  @override
  Future<List<MikrotikRouterConfig>> build() => RouterStore.load();

  Future<void> save(MikrotikRouterConfig router) async {
    await RouterStore.upsert(router);
    ref.invalidateSelf();
  }

  Future<void> remove(String id) async {
    await RouterStore.delete(id);
    ref.invalidateSelf();
  }
}

/// Result of a connection test performed from the setup screen.
final connectionTestProvider =
    StateProvider.autoDispose<AsyncValue<String>?>((ref) => null);

/// Currently connected router + live session snapshot for the dashboard.
/// Keyed by router id — each screen fetch manages its own session lifetime.
final routerSessionProvider = FutureProvider.autoDispose
    .family<RouterSnapshot, MikrotikRouterConfig>((ref, cfg) async {
  final svc = await RouterOsService.connect(cfg);
  ref.onDispose(svc.close);
  return RouterSnapshot.load(svc);
});

class RouterSnapshot {
  final Map<String, String> resource;
  final String identity;
  final List<Map<String, String>> users;
  final List<Map<String, String>> active;
  final List<Map<String, String>> profiles;

  RouterSnapshot({
    required this.resource,
    required this.identity,
    required this.users,
    required this.active,
    required this.profiles,
  });

  static Future<RouterSnapshot> load(RouterOsService svc) async {
    // Sequential on the same socket — RouterOS handles it fine and it
    // keeps untagged FIFO ordering simple.
    final resource = await svc.systemResource();
    final identity = await svc.identity();
    final users = await svc.hotspotUsers();
    final active = await svc.hotspotActive();
    final profiles = await svc.hotspotProfiles();
    return RouterSnapshot(
      resource: resource,
      identity: identity,
      users: users,
      active: active,
      profiles: profiles,
    );
  }

  int get cpuLoad => int.tryParse(resource['cpu-load'] ?? '0') ?? 0;

  int get memoryPercent {
    final total = int.tryParse(resource['total-memory'] ?? '0') ?? 0;
    final free = int.tryParse(resource['free-memory'] ?? '0') ?? 0;
    if (total <= 0) return 0;
    return (((total - free) / total) * 100).round();
  }

  String get uptime => resource['uptime'] ?? '—';
  String get version => resource['version'] ?? '—';
  String get board => resource['board-name'] ?? resource['platform'] ?? '—';
}
