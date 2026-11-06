import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/utils/json_helpers.dart';

/// One offline-captured write waiting to be pushed to /sync/push.
///
/// `clientOpId` is generated on-device and is the server's
/// idempotency key — pushing the same batch twice never double-posts.
class AccQueuedOp {
  const AccQueuedOp({
    required this.clientOpId,
    required this.opType,
    required this.payload,
    required this.label,
    required this.queuedAt,
    this.lastError,
  });

  final String clientOpId;
  final String opType;
  final Map<String, dynamic> payload;
  final String label;
  final String queuedAt;

  /// Last server-side reason when a previous push came back
  /// needs_review (kept queued for the next attempt).
  final String? lastError;

  Map<String, dynamic> toJson() => {
        'client_op_id': clientOpId,
        'op_type': opType,
        'payload': payload,
        'label': label,
        'queued_at': queuedAt,
      };

  factory AccQueuedOp.fromJson(Map j) => AccQueuedOp(
        clientOpId: j['client_op_id']?.toString() ?? '',
        opType: j['op_type']?.toString() ?? '',
        payload: j['payload'] is Map
            ? Map<String, dynamic>.from(j['payload'] as Map)
            : const {},
        label: j['label']?.toString() ?? '',
        queuedAt: j['queued_at']?.toString() ?? '',
        lastError: j['last_error']?.toString(),
      );

  AccQueuedOp withError(String? error) => AccQueuedOp(
        clientOpId: clientOpId,
        opType: opType,
        payload: payload,
        label: label,
        queuedAt: queuedAt,
        lastError: error,
      );
}

/// Offline write-queue for the accounting feature (ACC-12).
///
/// A dedicated lazily-opened Hive box keeps the queue fully inside
/// features/accounting — no shared-file changes. Write APIs call
/// [enqueue] when a request fails on connectivity; the sync engine
/// drains the box through POST /sync/push once back online.
class AccOfflineQueue {
  AccOfflineQueue._();

  static const boxName = 'acc_offline_ops';

  static Future<Box> _box() async =>
      Hive.isBoxOpen(boxName) ? Hive.box(boxName) : Hive.openBox(boxName);

  /// Queue a failed write for the next sync. Returns the op id.
  static Future<String> enqueue({
    required String opType,
    required Map<String, dynamic> payload,
    String? label,
    String? opId,
  }) async {
    final id = opId ??
        'op-${DateTime.now().microsecondsSinceEpoch}-'
            '${payload.hashCode.abs() % 100000}';
    final box = await _box();
    await box.put(id, {
      'client_op_id': id,
      'op_type': opType,
      'payload': payload,
      'label': label ?? opLabels[opType] ?? opType,
      'queued_at': DateTime.now().toIso8601String(),
      'last_error': null,
    });
    return id;
  }

  static Future<List<AccQueuedOp>> pending() async {
    final box = await _box();
    final ops = box.values
        .whereType<Map>()
        .map(AccQueuedOp.fromJson)
        .toList()
      ..sort((a, b) => a.queuedAt.compareTo(b.queuedAt));
    return ops;
  }

  static Future<int> pendingCount() async => (await _box()).length;

  /// Mark an op that came back needs_review — stays in the box with
  /// its server error so the user sees why it waits.
  static Future<void> flagError(String clientOpId, String message) async {
    final box = await _box();
    final raw = box.get(clientOpId);
    if (raw is Map) {
      final m = Map<String, dynamic>.from(raw);
      m['last_error'] = message;
      await box.put(clientOpId, m);
    }
  }

  static Future<void> remove(String clientOpId) async {
    final box = await _box();
    await box.delete(clientOpId);
  }

  /// Watch the box for UI badges (Hive emits on every put/delete).
  static Stream<BoxEvent> watch() async* {
    final box = await _box();
    yield* box.watch();
  }

  /// Arabic labels per op_type — same vocabulary as the server.
  static const opLabels = {
    'collection.create': 'تحصيل نقدي',
    'debt.create': 'تسجيل دين',
    'debt.pay': 'سداد دين',
    'expense.create': 'مصروف',
    'transfer.create': 'تحويل بين الصناديق',
    'dist.sale': 'بيع موزع',
    'pos.order': 'طلب حزم كروت',
    'pos.withdrawal': 'طلب سحب ربح',
    'pos.exchange': 'استبدال كروت بالنقاط',
    'stock.adjust': 'تسوية مخزون',
    'purchase.create': 'مشتريات',
    'return.create': 'مرتجع',
    'damaged.create': 'تالف',
  };
}

/// Shared `{success, message}` unwrapper for accounting write
/// endpoints — identical to each Api class's `_write`, plus an
/// optional offline fallback: on connectivity failure the op is
/// enqueued for /sync/push and the user gets a "saved locally"
/// message instead of an error. Server answers (validation, 4xx)
/// still throw normally.
Future<String> accWriteOrQueue(
  Future<Response> Function() call, {
  String? offlineOp,
  Map<String, dynamic>? offlinePayload,
}) async {
  try {
    final res = await call();
    final j = res.data is Map ? toMap(res.data) : null;
    if (j?['success'] == true) {
      return j!['message']?.toString() ?? 'تمت العملية';
    }
    throw Exception(j?['message']?.toString() ?? 'تعذر تنفيذ العملية');
  } on DioException catch (e) {
    if (offlineOp != null && isOfflineError(e)) {
      await AccOfflineQueue.enqueue(
        opType: offlineOp,
        payload: offlinePayload ?? const {},
      );
      return 'انقطع الاتصال — حُفظت العملية وستُزامَن تلقائياً';
    }
    final body = e.response?.data;
    final msg = body is Map ? body['message']?.toString() : null;
    throw Exception(
        (msg != null && msg.isNotEmpty)
            ? msg
            : (e.message ?? 'تعذر تنفيذ العملية'));
  }
}

/// True when the failure is connectivity (no server response) — a
/// 4xx/5xx is a real server answer and must NOT be queued.
bool isOfflineError(Object e) {
  if (e is! DioException) return false;
  if (e.type == DioExceptionType.connectionError ||
      e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.sendTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.unknown && e.error is SocketException) {
    return true;
  }
  return e.error is SocketException;
}
