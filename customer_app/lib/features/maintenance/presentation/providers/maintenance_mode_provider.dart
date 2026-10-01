import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/cache/hive_service.dart';
import '../../../../core/utils/connectivity_service.dart';

class MaintenanceModeState {
  final bool isActive;
  final String? title;
  final String? description;
  final String? image;

  const MaintenanceModeState({
    this.isActive = false,
    this.title,
    this.description,
    this.image,
  });

  factory MaintenanceModeState.fromJson(Map<String, dynamic> json) {
    return MaintenanceModeState(
      isActive: json['is_active'] == true,
      title: json['title']?.toString(),
      description: json['description']?.toString(),
      image: json['image']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'is_active': isActive,
        'title': title,
        'description': description,
        'image': image,
      };
}

final maintenanceModeProvider = StateNotifierProvider<MaintenanceModeNotifier, MaintenanceModeState>((ref) {
  return MaintenanceModeNotifier(ref);
});

class MaintenanceModeNotifier extends StateNotifier<MaintenanceModeState> {
  final Ref _ref;
  Timer? _timer;

  MaintenanceModeNotifier(this._ref) : super(const MaintenanceModeState()) {
    _loadCached();
    fetch();
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => fetch());
  }

  Future<void> _loadCached() async {
    final cached = HiveService.maintenanceBox.get('state');
    if (cached != null) {
      state = MaintenanceModeState.fromJson(Map<String, dynamic>.from(cached));
    }
  }

  Future<void> fetch() async {
    try {
      final online = await ConnectivityService.isConnected();
      if (!online) return;
      final api = _ref.read(apiClientProvider);
      final res = await api.get('/maintenance-mode/customer_app');
      final data = res.data['data'] ?? {};
      final newState = MaintenanceModeState.fromJson(Map<String, dynamic>.from(data));
      state = newState;
      await HiveService.maintenanceBox.put('state', newState.toJson());
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
