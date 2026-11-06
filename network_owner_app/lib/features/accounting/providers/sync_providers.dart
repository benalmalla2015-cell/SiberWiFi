import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../data/offline_queue.dart';
import '../data/sync_api.dart';

/// Shared client for the ACC-12 endpoints (sync/backup/doc-header).
final syncApiProvider = Provider<SyncApi>(
  (ref) => SyncApi(ref.watch(apiClientProvider)),
);

/// The offline → online engine draining the local op box.
final accSyncEngineProvider = Provider<AccSyncEngine>(
  (ref) => AccSyncEngine(ref.watch(syncApiProvider)),
);

/// Locally queued offline ops — rebuilds whenever the Hive box
/// changes (enqueue, push-ack remove, error flag).
final accLocalOpsProvider = StreamProvider<List<AccQueuedOp>>((ref) async* {
  yield await AccOfflineQueue.pending();
  await for (final _ in AccOfflineQueue.watch()) {
    yield await AccOfflineQueue.pending();
  }
});

/// Server queue attention list + counters (/sync/pending).
final accSyncPendingProvider = FutureProvider<
    ({SyncCounts counts, List<SyncQueueItem> ops})>(
  (ref) => ref.watch(syncApiProvider).pending(),
);

/// Full server op log, optionally filtered by status.
final accSyncQueueProvider = FutureProvider.family<
    ({SyncCounts counts, List<SyncQueueItem> ops}), String?>(
  (ref, status) => ref.watch(syncApiProvider).queue(status: status),
);

/// Registered backup snapshots.
final accBackupsProvider = FutureProvider<List<AccBackup>>(
  (ref) => ref.watch(syncApiProvider).backups(),
);

/// The printed-document header row.
final accDocHeaderProvider = FutureProvider<AccDocHeader>(
  (ref) => ref.watch(syncApiProvider).docHeader(),
);
