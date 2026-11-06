import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:network_owner_app/features/accounting/data/offline_queue.dart';

/// ACC-12 — the local offline op box: enqueue/pending/remove/
/// flagError roundtrips + the connectivity detector that decides
/// whether a failed write gets queued (offline) or thrown (server
/// answered with a real 4xx).
void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('acc_offline_test');
    Hive.init(tempDir.path);
  });

  setUp(() async {
    if (Hive.isBoxOpen(AccOfflineQueue.boxName)) {
      await Hive.box(AccOfflineQueue.boxName).clear();
    } else {
      final box = await Hive.openBox(AccOfflineQueue.boxName);
      await box.clear();
    }
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('enqueue stores the op with a device id and Arabic label',
      () async {
    final id = await AccOfflineQueue.enqueue(
      opType: 'collection.create',
      payload: {'party_type': 'person', 'amount': 500},
    );

    expect(id, isNotEmpty);
    expect(await AccOfflineQueue.pendingCount(), 1);

    final ops = await AccOfflineQueue.pending();
    expect(ops.single.clientOpId, id);
    expect(ops.single.opType, 'collection.create');
    expect(ops.single.label, 'تحصيل نقدي');
    expect(ops.single.payload['amount'], 500);
    expect(ops.single.queuedAt, isNotEmpty);
    expect(ops.single.lastError, isNull);
  });

  test('pending preserves FIFO order by queued_at', () async {
    final box = await Hive.openBox(AccOfflineQueue.boxName);
    await box.put('b', {
      'client_op_id': 'b',
      'op_type': 'expense.create',
      'payload': {},
      'label': 'مصروف',
      'queued_at': '2026-10-29T11:00:00',
    });
    await box.put('a', {
      'client_op_id': 'a',
      'op_type': 'collection.create',
      'payload': {},
      'label': 'تحصيل',
      'queued_at': '2026-10-29T10:00:00',
    });

    final ops = await AccOfflineQueue.pending();
    expect(ops.map((o) => o.clientOpId).toList(), ['a', 'b']);
  });

  test('remove retires a synced op', () async {
    final id = await AccOfflineQueue.enqueue(
      opType: 'dist.sale',
      payload: {'pos_id': 1, 'items': []},
    );
    await AccOfflineQueue.remove(id);
    expect(await AccOfflineQueue.pendingCount(), 0);
  });

  test('flagError keeps the op queued with the server reason',
      () async {
    final id = await AccOfflineQueue.enqueue(
      opType: 'collection.create',
      payload: {'amount': 100},
    );
    await AccOfflineQueue.flagError(id, 'الصندوق غير موجود');

    final op = (await AccOfflineQueue.pending()).single;
    expect(op.lastError, 'الصندوق غير موجود');
    expect(op.clientOpId, id);
  });

  test('queued op serializes to the /sync/push envelope', () async {
    final id = await AccOfflineQueue.enqueue(
      opType: 'pos.order',
      payload: {
        'items': [
          {'category_id': 3, 'qty': 2}
        ]
      },
      opId: 'fixed-id',
    );
    expect(id, 'fixed-id');

    final op = (await AccOfflineQueue.pending()).single;
    final j = op.toJson();
    expect(j['client_op_id'], 'fixed-id');
    expect(j['op_type'], 'pos.order');
    expect((j['payload'] as Map)['items'], isList);
    expect(j['queued_at'], isNotEmpty);
  });

  test('isOfflineError: connectivity failures queue, 4xx do not',
      () {
    final offline = DioException(
      requestOptions: RequestOptions(),
      type: DioExceptionType.connectionError,
      error: const SocketException('no route'),
    );
    expect(isOfflineError(offline), isTrue);

    final timeout = DioException(
      requestOptions: RequestOptions(),
      type: DioExceptionType.connectionTimeout,
    );
    expect(isOfflineError(timeout), isTrue);

    final server422 = DioException(
      requestOptions: RequestOptions(),
      type: DioExceptionType.badResponse,
      response: Response(
        requestOptions: RequestOptions(),
        statusCode: 422,
        data: {'message': 'بيانات غير مكتملة'},
      ),
    );
    expect(isOfflineError(server422), isFalse);

    expect(isOfflineError(Exception('other')), isFalse);
  });
}
