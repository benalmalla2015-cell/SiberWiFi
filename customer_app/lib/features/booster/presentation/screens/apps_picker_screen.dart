import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/platform/vpn_channel.dart';
import '../../../../core/utils/vpn_state.dart';

final _installedAppsProvider = FutureProvider.autoDispose<List<AppInfo>>(
  (_) => VpnChannel.getInstalledApps(),
);

final _searchQueryProvider = StateProvider.autoDispose<String>((_) => '');

class AppsPickerScreen extends ConsumerWidget {
  const AppsPickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apps = ref.watch(_installedAppsProvider);
    final query = ref.watch(_searchQueryProvider);
    final currentTarget = ref.watch(vpnProvider).targetApp;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('اختر التطبيق المستهدف'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textDark,
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              onChanged: (v) => ref.read(_searchQueryProvider.notifier).state = v,
              decoration: const InputDecoration(
                hintText: 'ابحث عن تطبيق...',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          Expanded(
            child: apps.when(
              data: (list) {
                final filtered = query.isEmpty
                    ? list
                    : list
                        .where((a) =>
                            a.appName.toLowerCase().contains(query.toLowerCase()) ||
                            a.packageName.toLowerCase().contains(query.toLowerCase()))
                        .toList();

                if (filtered.isEmpty) {
                  return const Center(
                    child: Text('لا توجد تطبيقات', style: TextStyle(fontFamily: 'Cairo', fontSize: 15, color: AppColors.textGray)),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final app = filtered[i];
                    final isSelected = currentTarget?.packageName == app.packageName;
                    return _AppTile(
                      app: app,
                      isSelected: isSelected,
                      onTap: () {
                        ref.read(vpnProvider.notifier).setTargetApp(app);
                        context.pop();
                      },
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
              error: (e, _) => Center(
                child: Text('حدث خطأ: $e', style: const TextStyle(fontFamily: 'Cairo')),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppTile extends StatelessWidget {
  final AppInfo app;
  final bool isSelected;
  final VoidCallback onTap;

  const _AppTile({required this.app, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.06) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isSelected ? AppColors.primary : AppColors.divider, width: isSelected ? 2 : 1),
        ),
        child: Row(
          children: [
            _AppIcon(iconBase64: app.iconBase64),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(app.appName, style: const TextStyle(fontFamily: 'Cairo', fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textDark)),
                  Text(app.packageName, style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: AppColors.textGray), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (isSelected) const Icon(Icons.check_circle_rounded, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}

class _AppIcon extends StatelessWidget {
  final String? iconBase64;
  const _AppIcon({this.iconBase64});

  @override
  Widget build(BuildContext context) {
    if (iconBase64 != null) {
      try {
        final bytes = base64Decode(iconBase64!);
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.memory(Uint8List.fromList(bytes), width: 44, height: 44, fit: BoxFit.cover),
        );
      } catch (_) {}
    }
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(color: AppColors.inputBg, borderRadius: BorderRadius.circular(10)),
      child: const Icon(Icons.android_rounded, color: AppColors.primary, size: 26),
    );
  }
}
