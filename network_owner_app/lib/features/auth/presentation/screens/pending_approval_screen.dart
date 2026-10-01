import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/cache/hive_service.dart';
import '../../../../core/utils/connectivity_service.dart';
import '../providers/auth_provider.dart';
import 'package:network_owner_app/features/networks/presentation/screens/add_edit_network_screen.dart';

class PendingApprovalScreen extends ConsumerStatefulWidget {
  const PendingApprovalScreen({super.key});

  @override
  ConsumerState<PendingApprovalScreen> createState() =>
      _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends ConsumerState<PendingApprovalScreen>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _network;
  Timer? _refreshTimer;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadNetwork();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _refreshApproval(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshApproval();
  }

  Future<void> _refreshApproval() async {
    await ref.read(authProvider.notifier).refreshUser();
    if (mounted) await _loadNetwork(showLoading: false);
  }

  Future<void> _loadNetwork({bool showLoading = true}) async {
    if (showLoading) setState(() => _loading = true);
    try {
      final online = await ConnectivityService.isConnected();
      if (!online) {
        final cached = HiveService.networksBox.get('my_network');
        if (cached != null) {
          setState(() {
            _network = Map<String, dynamic>.from(cached);
            _loading = false;
            _error = null;
          });
          return;
        }
        setState(() {
          _error = 'لا يوجد اتصال بالإنترنت ولا توجد بيانات محفوظة';
          _loading = false;
        });
        return;
      }

      final api = ref.read(apiClientProvider);
      final res = await api.get('/auth/my-network');
      if (res.data['success'] == true) {
        setState(() {
          _network = Map<String, dynamic>.from(res.data['data']);
          _loading = false;
          _error = null;
        });
        await HiveService.networksBox.put('my_network', _network);
      } else {
        setState(() {
          _error = res.data['message'] ?? 'تعذر تحميل البيانات';
          _loading = false;
        });
      }
    } catch (e) {
      // 401 means the stored token is invalid (e.g. account was suspended and
      // tokens revoked) — the session is dead, so log out to reach /login.
      if (e is DioException && e.response?.statusCode == 401) {
        await ref.read(authProvider.notifier).logout();
        return;
      }
      final online = await ConnectivityService.isConnected();
      if (!online) {
        final cached = HiveService.networksBox.get('my_network');
        if (cached != null) {
          setState(() {
            _network = Map<String, dynamic>.from(cached);
            _loading = false;
            _error = null;
          });
          return;
        }
      }
      setState(() {
        _error = 'تعذر تحميل بيانات الشبكة: $e';
        _loading = false;
      });
    }
  }

  Future<void> _logout() async {
    await ref.read(authProvider.notifier).logout();
    if (mounted) context.go('/login');
  }

  Future<void> _editNetwork() async {
    if (_network == null) return;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddEditNetworkScreen(network: _network),
      ),
    );
    if (result == true) {
      _loadNetwork();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E2D7D),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF16235F),
                    Color(0xFF1E2D7D),
                    Color(0xFF243490),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  stops: [0.0, 0.5, 1.0],
                ),
              ),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset(
                      'logo/logo.png',
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.hourglass_top,
                        color: Colors.white,
                        size: 56,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'طلبك قيد المراجعة',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'سيتم مراجعة بياناتك من قِبل الإدارة. ستتلقى إشعاراً عند الموافقة.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),
            // Content
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: _buildContent(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: const TextStyle(color: AppColors.error)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadNetwork,
              child: const Text('إعادة المحاولة'),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: 160,
              height: 44,
              child: _PendingLogoutButton(onPressed: _logout),
            ),
          ],
        ),
      );
    }
    if (_network == null) {
      return const Center(child: Text('لا توجد شبكة مسجلة'));
    }

    final n = _network!;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _buildStatusBadge(n['status'] ?? 'pending'),
        if ((n['background_image_url']?.toString().isNotEmpty ?? false) ||
            (n['cover_image_url']?.toString().isNotEmpty ?? false)) ...[
          const SizedBox(height: 18),
          _NetworkImages(
            backgroundUrl: n['background_image_url']?.toString(),
            coverUrl: n['cover_image_url']?.toString(),
          ),
        ],
        const SizedBox(height: 24),
        _buildInfoTile(Icons.wifi, 'اسم الشبكة', n['name'] ?? ''),
        _buildInfoTile(Icons.location_on, 'المنطقة', n['region'] ?? ''),
        _buildInfoTile(Icons.map, 'المديرية', n['directorate'] ?? ''),
        _buildInfoTile(
          Icons.description,
          'الوصف',
          n['description'] ?? 'غير متوفر',
        ),
        if (n['url'] != null && n['url'].toString().isNotEmpty)
          _buildInfoTile(Icons.link, 'رابط المشاركة', n['url']),
        const SizedBox(height: 32),
        SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _editNetwork,
            icon: const Icon(Icons.edit),
            label: const Text(
              'تعديل بيانات الشبكة',
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(height: 48, child: _PendingLogoutButton(onPressed: _logout)),
      ],
    );
  }

  Widget _buildStatusBadge(String status) {
    final isPending = status == 'pending';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isPending ? const Color(0xFFFFF3E0) : const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isPending ? Colors.orange : Colors.green),
      ),
      child: Row(
        children: [
          Icon(
            isPending ? Icons.access_time : Icons.check_circle,
            color: isPending ? Colors.orange : Colors.green,
          ),
          const SizedBox(width: 12),
          Text(
            isPending ? 'قيد المراجعة' : 'معتمد',
            style: TextStyle(
              color: isPending ? Colors.orange.shade800 : Colors.green.shade800,
              fontWeight: FontWeight.bold,
              fontFamily: 'Cairo',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textGray,
                    fontSize: 12,
                    fontFamily: 'Cairo',
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NetworkImages extends StatelessWidget {
  final String? backgroundUrl;
  final String? coverUrl;

  const _NetworkImages({required this.backgroundUrl, required this.coverUrl});

  @override
  Widget build(BuildContext context) {
    final imageUrl = backgroundUrl?.isNotEmpty == true
        ? backgroundUrl!
        : coverUrl!;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: 145,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(color: AppColors.inputBg),
            ),
            Container(color: Colors.black.withValues(alpha: 0.18)),
            if (coverUrl?.isNotEmpty == true)
              Align(
                alignment: Alignment.center,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    coverUrl!,
                    width: 116,
                    height: 96,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PendingLogoutButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _PendingLogoutButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.error),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'تسجيل الخروج',
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.error,
            ),
          ),
        ),
      ),
    );
  }
}
