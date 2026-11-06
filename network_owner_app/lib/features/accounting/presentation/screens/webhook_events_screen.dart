import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../mikrotik/presentation/widgets/ui_states.dart';
import '../../data/loyalty_api.dart';
import '../../providers/loyalty_providers.dart';

/// ACC-10 — WhatsApp event templates (PLAN §4/§2.5). Tab 1 manages
/// the acc_webhook_events rows (event → {placeholder} template +
/// preview + toggle); tab 2 lists due-debt reminders rendered
/// server-side and launches each over wa.me.
class WebhookEventsScreen extends StatelessWidget {
  const WebhookEventsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إشعارات واتساب'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'القوالب'),
              Tab(text: 'تذكير الديون'),
            ],
          ),
        ),
        body: Container(
          color: AppColors.inputBg,
          child: const TabBarView(
            children: [
              _TemplatesTab(),
              _DebtRemindersTab(),
            ],
          ),
        ),
        floatingActionButton: Builder(
          builder: (ctx) => FloatingActionButton.extended(
            onPressed: () => _openForm(ctx),
            backgroundColor: AppColors.primary,
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text('قالب',
                style: TextStyle(color: Colors.white)),
          ),
        ),
      ),
    );
  }

  static Future<void> _openForm(BuildContext context,
      [AccWebhookEventRow? row]) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _TemplateFormSheet(row: row),
    );
  }
}

class _TemplatesTab extends ConsumerWidget {
  const _TemplatesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(accWebhookEventsProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(accWebhookEventsProvider),
      child: eventsAsync.when(
        loading: () => const LoadingState(),
        error: (e, _) => ErrorRetry(
          message: 'تعذّر تحميل القوالب\n$e',
          onRetry: () => ref.invalidate(accWebhookEventsProvider),
        ),
        data: (rows) => rows.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 120),
                  EmptyState(
                      'لا توجد قوالب — أضف قالباً لأحداث البيع والتحصيل',
                      icon: Icons.message_outlined),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: rows.length,
                itemBuilder: (_, i) => _TemplateCard(row: rows[i]),
              ),
      ),
    );
  }
}

class _TemplateCard extends ConsumerWidget {
  final AccWebhookEventRow row;
  const _TemplateCard({required this.row});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.chat_bubble_outline,
                  size: 20,
                  color: row.isActive
                      ? AppColors.success
                      : AppColors.textLight),
              const SizedBox(width: 8),
              Expanded(
                child: Text(row.eventLabel,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: row.isActive
                            ? AppColors.textDark
                            : AppColors.textGray)),
              ),
              Text(row.event,
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.textLight)),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.inputBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(row.templateBody,
                style: const TextStyle(
                    fontSize: 12,
                    height: 1.6,
                    color: AppColors.textDark)),
          ),
          if (row.placeholders.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: row.placeholders
                  .map((p) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color:
                              AppColors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('{$p}',
                            style: const TextStyle(
                                fontSize: 9,
                                color: AppColors.primary)),
                      ))
                  .toList(),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _preview(context, ref),
                icon: const Icon(Icons.visibility_outlined, size: 16),
                label: const Text('معاينة',
                    style: TextStyle(fontSize: 11)),
              ),
              TextButton.icon(
                onPressed: () =>
                    WebhookEventsScreen._openForm(context, row),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('تعديل',
                    style: TextStyle(fontSize: 11)),
              ),
              TextButton.icon(
                onPressed: () async {
                  await ref
                      .read(loyaltyApiProvider)
                      .updateWebhookEvent(
                          row.id, {'is_active': !row.isActive});
                  ref.invalidate(accWebhookEventsProvider);
                },
                icon: Icon(
                    row.isActive
                        ? Icons.pause_circle_outline
                        : Icons.play_circle_outline,
                    size: 16),
                label: Text(row.isActive ? 'إيقاف' : 'تفعيل',
                    style: const TextStyle(fontSize: 11)),
              ),
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => _delete(context, ref),
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: AppColors.error),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _preview(BuildContext context, WidgetRef ref) async {
    try {
      final body =
          await ref.read(loyaltyApiProvider).previewWebhookEvent(row.id);
      if (!context.mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(row.eventLabel),
          content: Text(body.isEmpty ? '(فارغ)' : body),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إغلاق')),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف القالب'),
        content: const Text('سيتوقف إرسال إشعارات هذا الحدث.'),
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
      await ref.read(loyaltyApiProvider).deleteWebhookEvent(row.id);
      ref.invalidate(accWebhookEventsProvider);
    }
  }
}

class _TemplateFormSheet extends ConsumerStatefulWidget {
  final AccWebhookEventRow? row;
  const _TemplateFormSheet({this.row});

  @override
  ConsumerState<_TemplateFormSheet> createState() =>
      _TemplateFormSheetState();
}

class _TemplateFormSheetState extends ConsumerState<_TemplateFormSheet> {
  final _bodyCtrl = TextEditingController();
  String _event = 'sale.created';
  bool _busy = false;

  static const eventLabels = {
    'sale.created': 'بيع جديد',
    'sale.updated': 'تعديل بيع',
    'sale.deleted': 'حذف بيع',
    'collection.created': 'تحصيل جديد',
    'debt.due': 'دين مستحق',
  };

  @override
  void initState() {
    super.initState();
    final r = widget.row;
    if (r != null) {
      _event = r.event;
      _bodyCtrl.text = r.templateBody;
    }
  }

  @override
  void dispose() {
    _bodyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.row != null;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(editing ? 'تعديل القالب' : 'قالب جديد',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary)),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue:
                  eventLabels.containsKey(_event) ? _event : null,
              decoration: const InputDecoration(
                  labelText: 'الحدث', border: OutlineInputBorder()),
              items: eventLabels.entries
                  .map((e) => DropdownMenuItem(
                      value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) => setState(() => _event = v ?? _event),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bodyCtrl,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'نص الرسالة',
                hintText:
                    'مثال: بيع جديد لـ {pos_name} بقيمة {total} رقم {sale_no}',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'المتغيرات المتاحة: {pos_name} {party_name} {sale_no} {order_no} {total} {paid} {amount} {remaining} {currency} {date} {due_date}',
              style:
                  TextStyle(fontSize: 10, color: AppColors.textGray),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(editing ? 'حفظ' : 'إنشاء'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final body = _bodyCtrl.text.trim();
    if (body.isEmpty) {
      _toast('أدخل نص الرسالة');
      return;
    }
    setState(() => _busy = true);
    try {
      final api = ref.read(loyaltyApiProvider);
      final msg = widget.row == null
          ? await api.createWebhookEvent(
              {'event': _event, 'template_body': body})
          : await api.updateWebhookEvent(widget.row!.id,
              {'event': _event, 'template_body': body});
      _toast(msg);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''));
      setState(() => _busy = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _DebtRemindersTab extends ConsumerWidget {
  const _DebtRemindersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rowsAsync = ref.watch(accDebtDueProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(accDebtDueProvider),
      child: rowsAsync.when(
        loading: () => const LoadingState(),
        error: (e, _) => ErrorRetry(
          message: 'تعذّر تحميل التذكيرات\n$e',
          onRetry: () => ref.invalidate(accDebtDueProvider),
        ),
        data: (rows) => rows.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 120),
                  EmptyState(
                      'لا توجد ديون مستحقة — أو لم يُفعَّل قالب «دين مستحق»',
                      icon: Icons.alarm_off_outlined),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: rows.length,
                itemBuilder: (_, i) => _ReminderCard(row: rows[i]),
              ),
      ),
    );
  }
}

class _ReminderCard extends StatelessWidget {
  final AccDebtDueReminder row;
  const _ReminderCard({required this.row});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(row.partyName,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: AppColors.textDark)),
              ),
              Text(row.remaining.toStringAsFixed(0),
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.error)),
            ],
          ),
          if (row.dueDate != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('استحقاق: ${row.dueDate}',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textGray)),
            ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.inputBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(row.body,
                style: const TextStyle(
                    fontSize: 12,
                    height: 1.6,
                    color: AppColors.textDark)),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Clipboard.setData(
                      ClipboardData(text: row.body)),
                  icon: const Icon(Icons.copy_outlined, size: 16),
                  label: const Text('نسخ',
                      style: TextStyle(fontSize: 11)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: row.waUrl == null
                      ? null
                      : () => launchUrl(Uri.parse(row.waUrl!),
                          mode: LaunchMode.externalApplication),
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.success),
                  icon: const Icon(Icons.send_outlined, size: 16),
                  label: const Text('إرسال واتساب',
                      style: TextStyle(fontSize: 11)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
