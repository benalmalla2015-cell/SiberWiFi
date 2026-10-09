import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/router_model.dart';
import '../providers/mikrotik_provider.dart';

class RoutersScreen extends ConsumerWidget {
  const RoutersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routers = ref.watch(routersProvider);

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(title: const Text('أجهزة MikroTik')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/mikrotik/setup'),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('إضافة راوتر',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: routers.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('خطأ: $e')),
        data: (list) {
          if (list.isEmpty) {
            return _EmptyState(
                onAdd: () => context.push('/mikrotik/setup'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            itemBuilder: (_, i) => _RouterTile(router: list[i]),
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.router_outlined,
                  size: 44, color: AppColors.primary),
            ),
            const SizedBox(height: 20),
            const Text('لا توجد أجهزة MikroTik',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 8),
            const Text(
              'أضف راوترك الأول للبدء بإدارة المستخدمين وتوليد الكروت مباشرة من جهازك',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textGray, fontSize: 13),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('إضافة راوتر'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouterTile extends ConsumerWidget {
  final MikrotikRouterConfig router;
  const _RouterTile({required this.router});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.router, color: AppColors.primary),
        ),
        title: Text(router.name.isEmpty ? router.host : router.name,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          '${router.host}:${router.port}${router.useSsl ? ' • TLS' : ''}',
          style: const TextStyle(color: AppColors.textGray, fontSize: 12),
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: AppColors.textGray),
          onSelected: (v) async {
            if (v == 'edit') {
              context.push('/mikrotik/setup', extra: router);
            } else if (v == 'delete') {
              final ok = await _confirmDelete(context);
              if (ok == true) {
                await ref.read(routersProvider.notifier).remove(router.id);
              }
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('تعديل')),
            PopupMenuItem(
              value: 'delete',
              child: Text('حذف', style: TextStyle(color: AppColors.accent)),
            ),
          ],
        ),
        onTap: () => context.push('/mikrotik/dashboard', extra: router),
      ),
    );
  }

  Future<bool?> _confirmDelete(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('حذف الراوتر'),
        content: Text('هل تريد حذف "${router.name}" من الأجهزة المحفوظة؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }
}
