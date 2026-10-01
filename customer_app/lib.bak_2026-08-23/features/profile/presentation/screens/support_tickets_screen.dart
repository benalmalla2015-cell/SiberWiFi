import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/json_helpers.dart';

final supportTicketsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final response = await ref.read(apiClientProvider).get('/support-tickets');
  return toMapList(response.data['data']);
});

class SupportTicketsScreen extends ConsumerWidget {
  const SupportTicketsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tickets = ref.watch(supportTicketsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('الدعم الفني')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.accent,
        onPressed: () => _showNewTicketSheet(context, ref),
        icon: const Icon(Icons.add_comment_outlined),
        label: const Text('طلب جديد', style: TextStyle(fontFamily: 'Cairo')),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(supportTicketsProvider),
        child: tickets.when(
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
          error: (_, __) => ListView(children: const [SizedBox(height: 220), Center(child: Text('تعذر تحميل طلبات الدعم', style: TextStyle(fontFamily: 'Cairo', color: AppColors.textGray)))]),
          data: (items) => items.isEmpty
              ? ListView(children: const [SizedBox(height: 200), Icon(Icons.support_agent_outlined, size: 64, color: AppColors.textLight), SizedBox(height: 12), Center(child: Text('لا توجد طلبات دعم', style: TextStyle(fontFamily: 'Cairo', color: AppColors.textGray)))])
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, index) => _TicketCard(ticket: items[index]),
                ),
        ),
      ),
    );
  }

  void _showNewTicketSheet(BuildContext context, WidgetRef ref) {
    final subject = TextEditingController();
    final message = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(20, 24, 20, MediaQuery.of(sheetContext).viewInsets.bottom + 20),
        child: _NewTicketForm(subject: subject, message: message, onSubmitted: () => ref.invalidate(supportTicketsProvider)),
      ),
    ).whenComplete(() {
      subject.dispose();
      message.dispose();
    });
  }
}

class _TicketCard extends StatelessWidget {
  final Map<String, dynamic> ticket;
  const _TicketCard({required this.ticket});

  @override
  Widget build(BuildContext context) {
    final replied = ticket['reply']?.toString().isNotEmpty == true;
    final color = replied ? AppColors.success : AppColors.primary;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withValues(alpha: .22))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Expanded(child: Text(ticket['subject']?.toString() ?? '', style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold))), Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4), decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(8)), child: Text(replied ? 'تم الرد' : 'قيد المتابعة', style: TextStyle(fontFamily: 'Cairo', color: color, fontSize: 11)))]),
          const SizedBox(height: 8),
          Text(ticket['message']?.toString() ?? '', style: const TextStyle(fontFamily: 'Cairo', color: AppColors.textGray, height: 1.5)),
          if (replied) ...[const SizedBox(height: 12), Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: AppColors.success.withValues(alpha: .06), borderRadius: BorderRadius.circular(10)), child: Text(ticket['reply'].toString(), style: const TextStyle(fontFamily: 'Cairo', color: AppColors.textDark, height: 1.5)))],
        ],
      ),
    );
  }
}

class _NewTicketForm extends ConsumerStatefulWidget {
  final TextEditingController subject;
  final TextEditingController message;
  final VoidCallback onSubmitted;
  const _NewTicketForm({required this.subject, required this.message, required this.onSubmitted});

  @override
  ConsumerState<_NewTicketForm> createState() => _NewTicketFormState();
}

class _NewTicketFormState extends ConsumerState<_NewTicketForm> {
  bool _submitting = false;

  Future<void> _submit() async {
    if (widget.subject.text.trim().isEmpty || widget.message.text.trim().isEmpty) return;
    setState(() => _submitting = true);
    try {
      await ref.read(apiClientProvider).post('/support-tickets', data: {'subject': widget.subject.text.trim(), 'message': widget.message.text.trim()});
      widget.onSubmitted();
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر إرسال طلب الدعم'), backgroundColor: AppColors.accent));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    const Text('طلب دعم جديد', textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Cairo', fontSize: 18, fontWeight: FontWeight.bold)),
    const SizedBox(height: 16),
    TextField(controller: widget.subject, decoration: const InputDecoration(labelText: 'الموضوع')),
    const SizedBox(height: 12),
    TextField(controller: widget.message, maxLines: 4, decoration: const InputDecoration(labelText: 'كيف يمكننا مساعدتك؟', alignLabelWithHint: true)),
    const SizedBox(height: 18),
    ElevatedButton(onPressed: _submitting ? null : _submit, child: _submitting ? const CircularProgressIndicator(color: Colors.white) : const Text('إرسال الطلب')),
  ]);
}
