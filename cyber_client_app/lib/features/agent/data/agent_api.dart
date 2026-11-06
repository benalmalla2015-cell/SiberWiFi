import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';

final agentApiProvider = Provider<AgentApi>((ref) {
  return AgentApi(ref.read(apiClientProvider));
});

/// Backend calls for the agent flows (CYB-07):
/// auth → POST /auth/login (existing core endpoint, read-only reuse)
/// lookups → GET  /cyber/subscribers/{sim_no}
/// topup   → POST /cyber/topup            (idempotent by key)
/// ledgers → GET  /cyber/agent/{profile,earnings,topups}
class AgentApi {
  final ApiClient _api;
  AgentApi(this._api);

  /// Login + persist the session. Returns the user map.
  Future<Map<String, dynamic>> login({
    required String phone,
    required String password,
  }) async {
    final res = await _api.post('/auth/login', data: {
      'phone': phone,
      'password': password,
    });
    final token = res.data['token']?.toString() ?? '';
    final user = (res.data['user'] as Map?)?.cast<String, dynamic>() ?? {};
    if (token.isEmpty) {
      throw DioException(
        requestOptions: res.requestOptions,
        response: res,
        message: 'استجابة غير مكتملة من الخادم',
      );
    }
    await _api.saveAgentSession(token, jsonEncode(user));
    return user;
  }

  /// The agent role gate — 200 means this user may top up.
  Future<Map<String, dynamic>> profile() async {
    final res = await _api.get('/cyber/agent/profile');
    return (res.data['data'] as Map).cast<String, dynamic>();
  }

  /// Subscriber name lookup for the confirm step.
  Future<Map<String, dynamic>> lookupSubscriber(String simNo) async {
    final res = await _api.get('/cyber/subscribers/$simNo');
    return (res.data['data'] as Map).cast<String, dynamic>();
  }

  /// Credits the subscriber; [idempotencyKey] makes a network retry
  /// safe — the server returns the original record, never a second charge.
  Future<Map<String, dynamic>> topup({
    required String simNo,
    required double amount,
    required String idempotencyKey,
  }) async {
    final res = await _api.post('/cyber/topup', data: {
      'sim_no': simNo,
      'amount': amount,
      'idempotency_key': idempotencyKey,
    });
    return (res.data['data'] as Map).cast<String, dynamic>();
  }

  /// "أرباحي" — summary + commission ledger.
  Future<Map<String, dynamic>> earnings() async {
    final res = await _api.get('/cyber/agent/earnings');
    return (res.data['data'] as Map).cast<String, dynamic>();
  }

  /// "سجل عملياتي" — the agent's own top-up history.
  Future<List<Map<String, dynamic>>> topups() async {
    final res = await _api.get('/cyber/agent/topups');
    final data = res.data['data'];
    final list = data is Map ? data['data'] : data;
    return (list as List? ?? [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
  }

  Future<void> logout() async {
    try {
      await _api.post('/auth/logout');
    } catch (_) {
      // Best-effort — the token is cleared locally regardless.
    } finally {
      await _api.clearSession();
    }
  }
}
