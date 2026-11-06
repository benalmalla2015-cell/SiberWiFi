import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/utils/json_helpers.dart';
import 'offline_queue.dart';

/// One server-side queue row (acc_sync_queue) as /sync/* returns it.
class SyncQueueItem {
  const SyncQueueItem({
    required this.id,
    required this.opType,
    required this.label,
    required this.status,
    required this.attempts,
    this.clientOpId,
    this.lastError,
    this.refId,
    this.queuedAt,
    this.sentAt,
    this.createdAt,
  });

  final int id;
  final String? clientOpId;
  final String opType;
  final String label;
  final String status; // pending | sent | needs_review
  final int attempts;
  final String? lastError;
  final int? refId;
  final String? queuedAt;
  final String? sentAt;
  final String? createdAt;

  bool get needsReview => status == 'needs_review';
  bool get isPending => status == 'pending';

  static const statusLabels = {
    'pending': 'بانتظار المزامنة',
    'sent': 'مُزامَنة',
    'needs_review': 'تحتاج مراجعة',
  };
  String get statusLabel => statusLabels[status] ?? status;

  factory SyncQueueItem.fromJson(Map<String, dynamic> j) => SyncQueueItem(
        id: (j['id'] as num).toInt(),
        clientOpId: j['client_op_id']?.toString(),
        opType: j['op_type']?.toString() ?? '',
        label: j['label']?.toString() ?? '',
        status: j['status']?.toString() ?? 'pending',
        attempts: (j['attempts'] as num?)?.toInt() ?? 0,
        lastError: j['last_error']?.toString(),
        refId: (j['ref_id'] as num?)?.toInt(),
        queuedAt: j['queued_at']?.toString(),
        sentAt: j['sent_at']?.toString(),
        createdAt: j['created_at']?.toString(),
      );
}

/// Server queue counters ({pending, sent, needs_review}).
class SyncCounts {
  const SyncCounts({
    required this.pending,
    required this.sent,
    required this.needsReview,
  });

  final int pending;
  final int sent;
  final int needsReview;

  static const zero = SyncCounts(pending: 0, sent: 0, needsReview: 0);

  factory SyncCounts.fromJson(Map<String, dynamic> j) => SyncCounts(
        pending: (j['pending'] as num?)?.toInt() ?? 0,
        sent: (j['sent'] as num?)?.toInt() ?? 0,
        needsReview: (j['needs_review'] as num?)?.toInt() ?? 0,
      );
}

/// One per-op outcome inside the /sync/push response.
class SyncOpResult {
  const SyncOpResult({
    required this.clientOpId,
    required this.status,
    required this.message,
    this.refId,
  });

  final String? clientOpId;
  final String status; // sent | needs_review | replayed | rejected
  final String message;
  final int? refId;

  bool get succeeded => status == 'sent' || status == 'replayed';

  factory SyncOpResult.fromJson(Map<String, dynamic> j) => SyncOpResult(
        clientOpId: j['client_op_id']?.toString(),
        status: j['status']?.toString() ?? '',
        message: j['message']?.toString() ?? '',
        refId: (j['ref_id'] as num?)?.toInt(),
      );
}

/// A registered backup snapshot (acc_backups).
class AccBackup {
  const AccBackup({
    required this.id,
    required this.filename,
    required this.size,
    required this.tablesCount,
    required this.rowsCount,
    required this.checksum,
    required this.fileExists,
    this.createdAt,
  });

  final int id;
  final String filename;
  final int size;
  final int tablesCount;
  final int rowsCount;
  final String checksum;
  final bool fileExists;
  final String? createdAt;

  String get sizeLabel {
    if (size >= 1048576) return '${(size / 1048576).toStringAsFixed(1)} م.ب';
    if (size >= 1024) return '${(size / 1024).toStringAsFixed(1)} ك.ب';
    return '$size بايت';
  }

  factory AccBackup.fromJson(Map<String, dynamic> j) => AccBackup(
        id: (j['id'] as num).toInt(),
        filename: j['filename']?.toString() ?? '',
        size: (j['size'] as num?)?.toInt() ?? 0,
        tablesCount: (j['tables_count'] as num?)?.toInt() ?? 0,
        rowsCount: (j['rows_count'] as num?)?.toInt() ?? 0,
        checksum: j['checksum']?.toString() ?? '',
        fileExists: j['file_exists'] == true,
        createdAt: j['created_at']?.toString(),
      );
}

/// The printed-document header settings row (acc_doc_header).
class AccDocHeader {
  const AccDocHeader({
    this.businessName,
    this.subtitle,
    this.phone,
    this.address,
    this.footerText,
    required this.showLogo,
    required this.hasLogo,
  });

  final String? businessName;
  final String? subtitle;
  final String? phone;
  final String? address;
  final String? footerText;
  final bool showLogo;
  final bool hasLogo;

  factory AccDocHeader.fromJson(Map<String, dynamic> j) => AccDocHeader(
        businessName: j['business_name']?.toString(),
        subtitle: j['subtitle']?.toString(),
        phone: j['phone']?.toString(),
        address: j['address']?.toString(),
        footerText: j['footer_text']?.toString(),
        showLogo: j['show_logo'] == true,
        hasLogo: j['has_logo'] == true,
      );
}

/// Thin client for the ACC-12 sync/backup/doc-header endpoints —
/// same conventions as AccApi (writes return the Arabic message).
class SyncApi {
  SyncApi(this._api);

  final ApiClient _api;
  static const _base = '/network-owner/accounting';

  // ── Sync center ──────────────────────────────────────────────

  Future<({SyncCounts counts, List<SyncQueueItem> ops})> pending() async {
    final res = await _api.get('$_base/sync/pending');
    final j = res.data is Map ? toMap(res.data) : null;
    return (
      counts: SyncCounts.fromJson(toMap(j?['counts'])),
      ops: toMapList(j?['data']).map(SyncQueueItem.fromJson).toList(),
    );
  }

  Future<({SyncCounts counts, List<SyncQueueItem> ops})> queue(
      {String? status}) async {
    final res = await _api.get('$_base/sync/queue',
        params: status == null ? null : {'status': status});
    final j = res.data is Map ? toMap(res.data) : null;
    return (
      counts: SyncCounts.fromJson(toMap(j?['counts'])),
      ops:
          toMapList(j?['data']?['data']).map(SyncQueueItem.fromJson).toList(),
    );
  }

  /// Push offline ops — sent as a JSON string field so nested
  /// payloads (items arrays…) survive the multipart encoding.
  Future<({SyncCounts counts, List<SyncOpResult> results})> push(
      List<AccQueuedOp> ops) async {
    final res = await _api.post('$_base/sync/push', data: {
      'ops': jsonEncode(ops.map((o) => o.toJson()).toList()),
    });
    final j = res.data is Map ? toMap(res.data) : null;
    return (
      counts: SyncCounts.fromJson(toMap(j?['counts'])),
      results: toMapList(j?['results'])
          .map(SyncOpResult.fromJson)
          .toList(),
    );
  }

  Future<String> retry(int opId) async =>
      _write(() => _api.post('$_base/sync/$opId/retry'));

  Future<String> discard(int opId) async =>
      _write(() => _api.post('$_base/sync/$opId/discard'));

  // ── Backups ──────────────────────────────────────────────────

  Future<List<AccBackup>> backups() async {
    final res = await _api.get('$_base/backups');
    return toMapList(res.data?['data']?['data'])
        .map(AccBackup.fromJson)
        .toList();
  }

  Future<String> createBackup() async =>
      _write(() => _api.post('$_base/backup'));

  Future<String> restoreBackup(int id) async =>
      _write(() => _api.post('$_base/backups/$id/restore'));

  /// Register an uploaded snapshot file — becomes a restorable row.
  Future<String> importBackup(String filePath) async {
    final name = filePath.split(Platform.pathSeparator).last;
    return _write(() => _api.post('$_base/backups/import', data: {
          'file': MultipartFile.fromFileSync(filePath, filename: name),
        }));
  }

  /// Raw snapshot bytes — the caller picks where to save them.
  Future<List<int>> downloadBackup(int id) async {
    final res = await _api.dio.get<List<int>>(
      '$_base/backups/$id/download',
      options: Options(responseType: ResponseType.bytes),
    );
    return res.data ?? const [];
  }

  // ── Doc header ───────────────────────────────────────────────

  Future<AccDocHeader> docHeader() async {
    final res = await _api.get('$_base/doc-header');
    final j = res.data is Map ? toMap(res.data) : null;
    return AccDocHeader.fromJson(toMap(j?['data']));
  }

  Future<String> saveDocHeader(Map<String, dynamic> data) async =>
      _write(() => _api.put('$_base/doc-header', data: data));

  Future<String> uploadDocLogo(String filePath) async {
    final name = filePath.split(Platform.pathSeparator).last;
    return _write(() => _api.post('$_base/doc-header/logo', data: {
          'logo': MultipartFile.fromFileSync(filePath, filename: name),
        }));
  }

  Future<String> removeDocLogo() async =>
      _write(() => _api.delete('$_base/doc-header/logo'));

  /// Auth'd logo bytes for the settings preview (no public URL).
  Future<List<int>> docLogoBytes() async {
    final res = await _api.dio.get<List<int>>(
      '$_base/doc-header/logo',
      options: Options(responseType: ResponseType.bytes),
    );
    return res.data ?? const [];
  }

  /// Unwraps `{success, message}` — the message field is always the
  /// user-facing Arabic copy, whether success or failure.
  Future<String> _write(Future<Response> Function() call) async {
    try {
      final res = await call();
      final j = res.data is Map ? toMap(res.data) : null;
      if (j?['success'] == true) {
        return j!['message']?.toString() ?? 'تمت العملية';
      }
      throw Exception(j?['message']?.toString() ?? 'تعذر تنفيذ العملية');
    } on DioException catch (e) {
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      throw Exception(
          (msg != null && msg.isNotEmpty)
              ? msg
              : (e.message ?? 'تعذر تنفيذ العملية'));
    }
  }
}

/// What one flush of the local queue accomplished.
class SyncFlushReport {
  const SyncFlushReport({
    required this.attempted,
    required this.sent,
    required this.needsReview,
    required this.failed,
    this.message,
  });

  final int attempted;
  final int sent; // sent + replayed
  final int needsReview;
  final bool failed; // connectivity/server error mid-batch
  final String? message;

  bool get isEmpty => attempted == 0;
}

/// Offline → online engine: drains the Hive box through
/// POST /sync/push and retires acknowledged ops. Re-entrant safe —
/// overlapping flushes collapse onto the first.
class AccSyncEngine {
  AccSyncEngine(this._api);

  final SyncApi _api;
  bool _running = false;

  Future<SyncFlushReport> flush() async {
    if (_running) {
      return const SyncFlushReport(
          attempted: 0, sent: 0, needsReview: 0, failed: false);
    }
    _running = true;
    try {
      final ops = await AccOfflineQueue.pending();
      if (ops.isEmpty) {
        return const SyncFlushReport(
            attempted: 0, sent: 0, needsReview: 0, failed: false);
      }
      try {
        final res = await _api.push(ops);
        var sent = 0;
        var review = 0;
        for (final r in res.results) {
          final id = r.clientOpId;
          if (id == null) continue;
          if (r.succeeded) {
            sent++;
            await AccOfflineQueue.remove(id);
          } else {
            review++;
            await AccOfflineQueue.flagError(id, r.message);
          }
        }
        return SyncFlushReport(
          attempted: ops.length,
          sent: sent,
          needsReview: review,
          failed: false,
        );
      } on DioException catch (e) {
        return SyncFlushReport(
          attempted: ops.length,
          sent: 0,
          needsReview: 0,
          failed: true,
          message: e.message,
        );
      }
    } finally {
      _running = false;
    }
  }
}
