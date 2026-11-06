import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/connectivity_service.dart';
import '../../../mikrotik/presentation/widgets/ui_states.dart';
import '../../data/offline_queue.dart';
import '../../data/sync_api.dart';
import '../../providers/sync_providers.dart';

/// ACC-12 — the sync center (PLAN §5: sync_screen).
///
/// Top card: connectivity state + queue counters + "مزامنة الآن".
/// Local section: offline ops still waiting in the device box —
/// swiping left deletes one (it never reached the server).
/// Server section: the queue's needs_review rows with retry/discard.
class AccSyncCenterScreen extends ConsumerWidget {
  const AccSyncCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(isOnlineProvider);
    final localAsync = ref.watch(accLocalOpsProvider);
    final pendingAsync = ref.watch(accSyncPendingProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('مركز المزامنة'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: () {
              ref.invalidate(accSyncPendingProvider);
              ref.invalidate(accSyncQueueProvider);
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Container(
        color: AppColors.inputBg,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(accSyncPendingProvider);
            ref.invalidate(accSyncQueueProvider);
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _StatusCard(
                online: online,
                local: localAsync.valueOrNull ?? const [],
                counts: pendingAsync.valueOrNull?.counts ?? SyncCounts.zero,
              ),
              const SizedBox(height: 16),
              localAsync.when(
                loading: () => const LoadingState(),
                error: (e, _) => Text('تعذّر قراءة الطابور المحلي: $e',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.error)),
                data: (ops) => _LocalOpsSection(ops: ops),
              ),
              const SizedBox(height: 16),
              pendingAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => ErrorRetry(
                  message: 'تعذّر تحميل طابور الخادم\n$e',
                  onRetry: () => ref.invalidate(accSyncPendingProvider),
                ),
                data: (res) => _ServerOpsSection(ops: res.ops),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Status card ────────────────────────────────────────────────

class _StatusCard extends ConsumerStatefulWidget {
  const _StatusCard({
    required this.online,
    required this.local,
    required this.counts,
  });

  final bool online;
  final List<AccQueuedOp> local;
  final SyncCounts counts;

  @override
  ConsumerState<_StatusCard> createState() => _StatusCardState();
}

class _StatusCardState extends ConsumerState<_StatusCard> {
  bool _syncing = false;

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    try {
      final report = await ref.read(accSyncEngineProvider).flush();
      ref.invalidate(accSyncPendingProvider);
      ref.invalidate(accSyncQueueProvider);
      if (!mounted) return;
      final msg = report.failed
          ? 'تعذّرت المزامنة — تحقّق من الاتصال'
          : report.isEmpty
              ? 'لا عمليات بانتظار المزامنة'
              : 'زُامِنَت ${report.sent} عملية'
                  '${report.needsReview > 0 ? ' • ${report.needsReview} تحتاج مراجعة' : ''}';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final waiting = widget.local.length + widget.counts.needsReview;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                widget.online ? Icons.cloud_done : Icons.cloud_off,
                color: widget.online ? AppColors.success : AppColors.error,
              ),
              const SizedBox(width: 8),
              Text(
                widget.online ? 'متصل بالإنترنت' : 'غير متصل — وضع offline',
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _countChip('محلية بانتظار الإرسال', widget.local.length,
                  AppColors.primary),
              const SizedBox(width: 8),
              _countChip('تحتاج مراجعة', widget.counts.needsReview,
                  AppColors.error),
              const SizedBox(width: 8),
              _countChip('مُزامَنة', widget.counts.sent, AppColors.success),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed:
                  (_syncing || !widget.online || waiting == 0)
                      ? null
                      : _syncNow,
              icon: _syncing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.sync, color: Colors.white),
              label: Text(
                _syncing ? 'جارٍ المزامنة…' : 'مزامنة الآن',
                style: const TextStyle(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _countChip(String label, int count, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Text('$count',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color)),
              Text(label,
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(fontSize: 10, color: AppColors.textGray)),
            ],
          ),
        ),
      );
}

// ── Local ops (device queue) ───────────────────────────────────

class _LocalOpsSection extends ConsumerWidget {
  const _LocalOpsSection({required this.ops});

  final List<AccQueuedOp> ops;

  Future<void> _drop(
      BuildContext context, WidgetRef ref, AccQueuedOp op) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف العملية؟'),
        content: Text(
            '"${op.label}" لم تصل الخادم — حذفها يعني فقدانها نهائياً.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (ok == true) {
      await AccOfflineQueue.remove(op.clientOpId);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('عمليات الجهاز (offline)'),
        const SizedBox(height: 8),
        if (ops.isEmpty)
          const EmptyState('لا عمليات محلية بانتظار الإرسال',
              icon: Icons.check_circle_outline)
        else
          ...ops.map((op) => Dismissible(
                key: ValueKey(op.clientOpId),
                direction: DismissDirection.endToStart,
                confirmDismiss: (_) async {
                  await _drop(context, ref, op);
                  return false; // remove() rebuilds via the box watch
                },
                background: Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child:
                      const Icon(Icons.delete_outline, color: Colors.white),
                ),
                child: _OpTile(
                  icon: Icons.schedule,
                  iconColor: op.lastError != null
                      ? AppColors.error
                      : AppColors.primary,
                  title: op.label,
                  subtitle: op.lastError ??
                      'بانتظار المزامنة • ${_shortDate(op.queuedAt)}',
                  error: op.lastError != null,
                ),
              )),
      ],
    );
  }
}

// ── Server ops (needs_review attention) ────────────────────────

class _ServerOpsSection extends ConsumerWidget {
  const _ServerOpsSection({required this.ops});

  final List<SyncQueueItem> ops;

  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    SyncQueueItem op,
    Future<String> Function(SyncApi api) call,
  ) async {
    try {
      final msg = await call(ref.read(syncApiProvider));
      ref.invalidate(accSyncPendingProvider);
      ref.invalidate(accSyncQueueProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('طابور الخادم — تحتاج انتباه'),
        const SizedBox(height: 8),
        if (ops.isEmpty)
          const EmptyState('الطابور نظيف — لا عمليات معلّقة',
              icon: Icons.done_all)
        else
          ...ops.map((op) => _OpTile(
                icon: op.needsReview
                    ? Icons.warning_amber_rounded
                    : Icons.hourglass_top,
                iconColor: op.needsReview
                    ? AppColors.error
                    : AppColors.primary,
                title: op.label,
                subtitle:
                    '${op.statusLabel} • ${op.attempts} محاولة'
                    '${op.lastError != null ? '\n${op.lastError}' : ''}',
                error: op.needsReview,
                trailing: op.needsReview
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'إعادة المحاولة',
                            icon: const Icon(Icons.refresh,
                                color: AppColors.primary, size: 20),
                            onPressed: () => _act(context, ref, op,
                                (api) => api.retry(op.id)),
                          ),
                          IconButton(
                            tooltip: 'استبعاد',
                            icon: const Icon(Icons.close,
                                color: AppColors.error, size: 20),
                            onPressed: () => _act(context, ref, op,
                                (api) => api.discard(op.id)),
                          ),
                        ],
                      )
                    : null,
              )),
      ],
    );
  }
}

// ── Shared bits ────────────────────────────────────────────────

Widget _sectionTitle(String text) => Text(
      text,
      style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: AppColors.textDark),
    );

class _OpTile extends StatelessWidget {
  const _OpTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.error = false,
    this.trailing,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool error;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: error ? AppColors.error.withValues(alpha: 0.4) : AppColors.divider),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark)),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 11,
                        color:
                            error ? AppColors.error : AppColors.textGray)),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

String _shortDate(String iso) =>
    iso.length >= 16 ? iso.substring(0, 16).replaceFirst('T', ' ') : iso;
