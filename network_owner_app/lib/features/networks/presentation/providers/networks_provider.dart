import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/networks_repository.dart';

final networksProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return ref.read(networksRepositoryProvider).getNetworks();
});

final categoriesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return ref.read(networksRepositoryProvider).getCategories();
});

final selectedNetworkIdProvider = StateProvider<int?>((ref) => null);
final selectedCardStatusProvider = StateProvider<String>((ref) => 'all');

final cardsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final networkId = ref.watch(selectedNetworkIdProvider);
  final status    = ref.watch(selectedCardStatusProvider);
  return ref.read(networksRepositoryProvider).getCards(
    networkId: networkId,
    status: status == 'all' ? null : status,
  );
});
