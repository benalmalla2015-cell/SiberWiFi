import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../mikrotik/presentation/widgets/ui_states.dart';
import '../../data/sync_api.dart';
import '../../providers/sync_providers.dart';

/// ACC-12 — backup export/restore (PLAN §5: backup_screen).
///
/// Header action creates a snapshot; each row offers تنزيل (saves
/// the JSON under the app's documents dir) and استعادة (a confirm-
/// gated atomic restore server-side). The import button registers
/// an external snapshot file.
class AccBackupScreen extends ConsumerWidget {
  const AccBackupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backupsAsync = ref.watch(accBackupsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('النسخ الاحتياطي'),
        actions: [
          IconButton(
            tooltip: 'استيراد نسخة من ملف',
            onPressed: () => _import(context, ref),
            icon: const Icon(Icons.upload_file_outlined),
          ),
          IconButton(
            tooltip: 'نسخة جديدة',
            onPressed: () => _create(context, ref),
            icon: const Icon(Icons.add_to_photos_outlined),
          ),
        ],
      ),
      body: Container(
        color: AppColors.inputBg,
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(accBackupsProvider),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'النسخة تشمل كل بيانات المحاسبة (acc_*) لهذا الحساب. '
                  'الاستعادة تستبدل الحالة الحالية بالكامل دفعةً واحدة.',
                  style: TextStyle(fontSize: 11, color: AppColors.textGray),
                ),
              ),
              backupsAsync.when(
                loading: () => const LoadingState(),
                error: (e, _) => ErrorRetry(
                  message: 'تعذّر تحميل النسخ\n$e',
                  onRetry: () => ref.invalidate(accBackupsProvider),
                ),
                data: (backups) => backups.isEmpty
                    ? const EmptyState('لا نسخ احتياطية بعد',
                        icon: Icons.backup_outlined)
                    : Column(
                        children: backups
                            .map((b) => _BackupTile(backup: b))
                            .toList(),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    try {
      final msg = await ref.read(syncApiProvider).createBackup();
      ref.invalidate(accBackupsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    final path = picked?.files.single.path;
    if (path == null) return;
    try {
      final msg = await ref.read(syncApiProvider).importBackup(path);
      ref.invalidate(accBackupsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }
}

class _BackupTile extends ConsumerWidget {
  const _BackupTile({required this.backup});

  final AccBackup backup;

  Future<void> _download(BuildContext context, WidgetRef ref) async {
    try {
      final bytes = await ref.read(syncApiProvider).downloadBackup(backup.id);
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}${backup.filename}');
      await file.writeAsBytes(bytes, flush: true);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('حُفظت النسخة في\n${file.path}')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('استعادة النسخة؟'),
        content: Text(
            'سيتم استبدال كل بيانات المحاسبة الحالية بمحتوى '
            '"${backup.filename}" (${backup.rowsCount} سجلاً). '
            'هذا الإجراء لا يمكن التراجع عنه.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('استعادة')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final msg = await ref.read(syncApiProvider).restoreBackup(backup.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = backup.createdAt != null && backup.createdAt!.length >= 16
        ? backup.createdAt!.substring(0, 16).replaceFirst('T', ' ')
        : '';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Icon(
            backup.fileExists ? Icons.backup : Icons.backup_outlined,
            color: backup.fileExists ? AppColors.primary : AppColors.textGray,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(backup.filename,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark)),
                Text(
                  '$date • ${backup.sizeLabel} • '
                  '${backup.tablesCount} جدول • ${backup.rowsCount} سجل'
                  '${backup.fileExists ? '' : ' • الملف مفقود'}',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textGray),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'تنزيل',
            icon: const Icon(Icons.download_outlined,
                color: AppColors.primary, size: 20),
            onPressed:
                backup.fileExists ? () => _download(context, ref) : null,
          ),
          IconButton(
            tooltip: 'استعادة',
            icon: const Icon(Icons.settings_backup_restore,
                color: AppColors.error, size: 20),
            onPressed:
                backup.fileExists ? () => _restore(context, ref) : null,
          ),
        ],
      ),
    );
  }
}
