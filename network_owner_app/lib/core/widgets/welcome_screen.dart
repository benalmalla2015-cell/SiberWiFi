import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../cache/hive_service.dart';
import '../theme/app_theme.dart';

const _kWelcomeSeenKey = 'has_seen_welcome';

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final PageController _controller = PageController();
  int _index = 0;
  final List<String> _imagePaths = [];
  bool _loading = true;
  bool _didLoadImages = false;
  Timer? _autoPlayTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoadImages) return;
    _didLoadImages = true;
    _loadImages();
  }

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadImages() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(
        DefaultAssetBundle.of(context),
      );
      final paths = manifest
          .listAssets()
          .where((k) => k.startsWith('Wellcome/') && _isImage(k))
          .toList();
      paths.sort();
      if (mounted) {
        setState(() {
          _imagePaths.addAll(paths);
          _loading = false;
        });
      }
      if (paths.length > 1) {
        _autoPlayTimer = Timer.periodic(
          const Duration(seconds: 4),
          (_) => _nextPage(),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isImage(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif');
  }

  void _nextPage() {
    if (!mounted || _imagePaths.isEmpty) return;
    final next = (_index + 1) % _imagePaths.length;
    _controller.animateToPage(
      next,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _finish() async {
    await markWelcomeSeen();
    if (!mounted) return;
    final status = ref.read(authProvider).status;
    if (status == AuthStatus.authenticated) {
      context.go('/');
    } else {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryDark,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_loading)
            const Center(child: CircularProgressIndicator(color: Colors.white))
          else if (_imagePaths.isNotEmpty)
            PageView.builder(
              controller: _controller,
              onPageChanged: (i) => setState(() => _index = i),
              itemCount: _imagePaths.length,
              itemBuilder: (_, i) => Image.asset(
                _imagePaths[i],
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
            )
          else
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.primary, AppColors.primaryDark],
                ),
              ),
            ),
          PositionedDirectional(
            top: MediaQuery.paddingOf(context).top + 12,
            end: 18,
            child: TextButton(
              onPressed: _finish,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.black.withValues(alpha: 0.28),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                shape: const StadiumBorder(),
              ),
              child: const Text(
                'تخطي',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          if (_imagePaths.length > 1)
            Positioned(
              right: 0,
              left: 0,
              bottom: MediaQuery.paddingOf(context).bottom + 24,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _imagePaths.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _index == i ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _index == i ? Colors.white : Colors.white54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Future<bool> shouldShowWelcome() async {
  return !(HiveService.dashboardBox.get(_kWelcomeSeenKey) as bool? ?? false);
}

Future<void> markWelcomeSeen() async {
  await HiveService.dashboardBox.put(_kWelcomeSeenKey, true);
}
