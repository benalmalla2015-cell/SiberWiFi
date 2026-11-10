import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/utils/json_helpers.dart';
import '../../data/fiber_topup_models.dart';

/// The fixed-line service (`post` — landline / ADSL / FTTH) from the
/// server-driven top-up catalog.
final fiberServiceProvider = FutureProvider<FiberService>((ref) async {
  final api = ref.read(apiClientProvider);
  final res = await api.get('/topup/services');
  final services =
      toMapList(res.data['data']).map(FiberService.fromJson).toList();
  final service = services.where((s) => s.code == 'post').firstOrNull;
  if (service == null) throw 'خدمة الهاتف الثابت غير متوفرة حالياً';
  return service;
});

/// Server-side price/fee/conversion preview for a package code.
/// Free to call — used to show the exact wallet charge before paying.
final fiberQuoteProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, packageCode) async {
  final api = ref.read(apiClientProvider);
  final res = await api.get('/topup/quote', params: {
    'service': 'post',
    'package': packageCode,
  });
  return toMap(res.data['data']);
});

/// The user's recent top-up orders (history sheet).
final fiberOrdersProvider = FutureProvider<List<FiberOrder>>((ref) async {
  final api = ref.read(apiClientProvider);
  final res = await api.get('/topup/orders');
  return toMapList(res.data['data'])
      .map(FiberOrder.fromJson)
      .where((o) => true)
      .toList();
});

class FiberTopupNotifier extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;
  FiberTopupNotifier(this._ref) : super(const AsyncValue.data(null));

  /// Pays a package activation. The server re-prices the package itself —
  /// [amount] is sent only to satisfy request validation and is never
  /// trusted server-side. Returns the API response data on success and
  /// throws the server's Arabic message on failure.
  Future<Map<String, dynamic>> pay({
    required String num,
    required FiberPackage package,
  }) async {
    state = const AsyncValue.loading();
    try {
      final api = _ref.read(apiClientProvider);
      final res = await api.post('/topup/pay', data: {
        'service': 'post',
        'num': num,
        'package': package.code,
        'amount': package.price, // validation only — price is server-resolved
        'type': package.serviceType,
      });
      state = const AsyncValue.data(null);
      return toMap(res.data['data'] ?? res.data);
    } catch (e) {
      state = const AsyncValue.data(null);
      rethrow;
    }
  }
}

final fiberTopupProvider =
    StateNotifierProvider<FiberTopupNotifier, AsyncValue<void>>(
        (ref) => FiberTopupNotifier(ref));
