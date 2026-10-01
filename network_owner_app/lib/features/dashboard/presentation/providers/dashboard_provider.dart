import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/dashboard_repository.dart';

final selectedPeriodProvider = StateProvider<String>((ref) => 'week');

final dashboardDataProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final repo = ref.read(dashboardRepositoryProvider);
  return repo.getDashboard();
});

final statsDataProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final period = ref.watch(selectedPeriodProvider);
  final repo   = ref.read(dashboardRepositoryProvider);
  return repo.getStats(period);
});
