import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/cache/hive_service.dart';
import '../../../../core/utils/connectivity_service.dart';

List<Map<String, dynamic>> _castCachedList(dynamic cached) {
  if (cached == null) return [];
  if (cached is List) {
    return cached.map((item) {
      if (item is Map<String, dynamic>) return item;
      if (item is Map) return Map<String, dynamic>.from(item);
      return <String, dynamic>{};
    }).toList();
  }
  return [];
}

final reportsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final online = await ConnectivityService.isConnected();
  if (!online) {
    final c = HiveService.networksBox.get('reports');
    if (c != null) return _castCachedList(c);
    return [];
  }
  try {
    final api  = ref.read(apiClientProvider);
    final res  = await api.get('/network-owner/reports');
    final list = List<Map<String, dynamic>>.from(res.data['data'] ?? []);
    await HiveService.networksBox.put('reports', list);
    return list;
  } catch (_) {
    final c = HiveService.networksBox.get('reports');
    if (c != null) return _castCachedList(c);
    return [];
  }
});

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsAsync = ref.watch(reportsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('البلاغات')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(reportsProvider),
        child: reportsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error:   (e, _) => Center(child: Text('خطأ: $e')),
          data: (reports) {
            if (reports.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.report_off_outlined, size: 64, color: AppColors.divider),
                    SizedBox(height: 12),
                    Text('لا توجد بلاغات', style: TextStyle(color: AppColors.textGray, fontSize: 16)),
                  ],
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: reports.length,
              itemBuilder: (_, i) => _ReportCard(
                report: reports[i],
                onReply: () => ref.invalidate(reportsProvider),
                ref: ref,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ReportCard extends StatefulWidget {
  final Map<String, dynamic> report;
  final VoidCallback onReply;
  final WidgetRef ref;
  const _ReportCard({required this.report, required this.onReply, required this.ref});

  @override
  State<_ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends State<_ReportCard> {
  bool _expanded = false;

  Color _statusColor(String s) {
    switch (s) {
      case 'open':     return AppColors.error;
      case 'replied':
      case 'resolved': return AppColors.success;
      case 'closed':   return AppColors.textGray;
      default:         return AppColors.warning;
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'open':     return 'مفتوح';
      case 'replied':
      case 'resolved': return 'تم الرد';
      case 'closed':   return 'مغلق';
      default:         return s;
    }
  }

  @override
  Widget build(BuildContext context) {
    final r        = widget.report;
    final status   = r['status'] ?? 'open';
    final subject  = r['subject'] ?? r['title'] ?? 'بلاغ';
    final body     = r['body']    ?? r['message'] ?? '';
    final reply    = r['reply']   ?? r['admin_reply'] ?? '';
    final client   = r['user']?['name'] ?? r['user_name'] ?? r['client_name'] ?? 'عميل';
    final network  = r['network']?['name'] ?? '';
    final date     = r['created_at']?.toString().substring(0, 10) ?? '';
    final hasReply = reply.isNotEmpty;
    final color    = _statusColor(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.report_problem_outlined, color: color, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(subject, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text('$client${network.isNotEmpty ? ' · $network' : ''}', style: const TextStyle(color: AppColors.textGray, fontSize: 12)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                          child: Text(_statusLabel(status), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(height: 2),
                        Text(date, style: const TextStyle(color: AppColors.textGray, fontSize: 10)),
                      ],
                    ),
                  ],
                ),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    _expanded ? body : (body.length > 100 ? '${body.substring(0, 100)}...' : body),
                    style: const TextStyle(fontSize: 13, color: AppColors.textDark, height: 1.5),
                  ),
                  if (body.length > 100)
                    GestureDetector(
                      onTap: () => setState(() => _expanded = !_expanded),
                      child: Text(
                        _expanded ? 'عرض أقل' : 'عرض المزيد',
                        style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
                if (hasReply) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.success.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.reply, color: AppColors.success, size: 16),
                        const SizedBox(width: 8),
                        Expanded(child: Text(reply, style: const TextStyle(fontSize: 12, color: AppColors.textDark))),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!hasReply)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _showReplyDialog(context),
                  icon: const Icon(Icons.reply, size: 16),
                  label: const Text('الرد على البلاغ', style: TextStyle(fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showReplyDialog(BuildContext ctx) {
    final ctr = TextEditingController();
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _ReplySheet(
        reportId: widget.report['id'],
        controller: ctr,
        ref: widget.ref,
        onSuccess: widget.onReply,
      ),
    );
  }
}

class _ReplySheet extends ConsumerStatefulWidget {
  final int reportId;
  final TextEditingController controller;
  final WidgetRef ref;
  final VoidCallback onSuccess;
  const _ReplySheet({required this.reportId, required this.controller, required this.ref, required this.onSuccess});

  @override
  ConsumerState<_ReplySheet> createState() => _ReplySheetState();
}

class _ReplySheetState extends ConsumerState<_ReplySheet> {
  bool _loading = false;

  Future<void> _send() async {
    if (widget.controller.text.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.post('/network-owner/reports/${widget.reportId}/reply', data: {'reply': widget.controller.text.trim()});
      if (mounted) {
        Navigator.pop(context);
        widget.onSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرسال الرد بنجاح'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('الرد على البلاغ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          TextField(
            controller: widget.controller,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'اكتب ردك هنا...',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loading ? null : _send,
            icon: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.send),
            label: const Text('إرسال الرد'),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
