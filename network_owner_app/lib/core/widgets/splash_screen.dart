import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import 'welcome_screen.dart';
// ignore: unused_import
export '../../features/auth/presentation/providers/auth_provider.dart' show AuthStatus;

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _textController;
  late AnimationController _pulseController;

  late Animation<double>  _logoScale;
  late Animation<double>  _logoOpacity;
  late Animation<double>  _textOpacity;
  late Animation<Offset>  _textSlide;
  late Animation<double>  _pulse;

  @override
  void initState() {
    super.initState();

    _logoController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _textController = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400), reverseDuration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);

    _logoScale   = CurvedAnimation(parent: _logoController, curve: Curves.elasticOut).drive(Tween(begin: 0.3, end: 1.0));
    _logoOpacity = CurvedAnimation(parent: _logoController, curve: Curves.easeIn).drive(Tween(begin: 0.0, end: 1.0));
    _textOpacity = CurvedAnimation(parent: _textController, curve: Curves.easeIn).drive(Tween(begin: 0.0, end: 1.0));
    _textSlide   = CurvedAnimation(parent: _textController, curve: Curves.easeOut).drive(
      Tween(begin: const Offset(0, 0.4), end: Offset.zero),
    );
    _pulse = CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut).drive(Tween(begin: 1.0, end: 1.08));

    _startSequence();
  }

  Future<void> _startSequence() async {
    await Future.delayed(const Duration(milliseconds: 200));
    await _logoController.forward();
    await Future.delayed(const Duration(milliseconds: 100));
    await _textController.forward();
    // Wait for auth check to complete (max 4 seconds)
    await _waitForAuthResolved();
    _navigate();
  }

  Future<void> _waitForAuthResolved() async {
    const maxWait = Duration(seconds: 4);
    final deadline = DateTime.now().add(maxWait);
    while (mounted) {
      final s = ref.read(authProvider).status;
      if (s != AuthStatus.unknown) return;
      if (DateTime.now().isAfter(deadline)) return;
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  void _navigate() async {
    if (!mounted) return;
    final authState = ref.read(authProvider);
    final showWelcome = await shouldShowWelcome();
    if (!mounted) return;
    if (showWelcome) {
      context.go('/welcome');
      return;
    }
    if (authState.status == AuthStatus.authenticated) {
      context.go('/');
    } else {
      context.go('/login');
    }
  }

  @override
  void dispose() {
    _logoController.dispose();
    _textController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF16235F), // primaryDark
              Color(0xFF1E2D7D), // primary
              Color(0xFF243490), // mid
              Color(0xFF1E2D7D), // primary
            ],
            stops: [0.0, 0.35, 0.70, 1.0],
          ),
        ),
        child: Stack(
          children: [
            _buildBackgroundDecoration(),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildLogo(),
                  const SizedBox(height: 32),
                  _buildText(),
                ],
              ),
            ),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildBackgroundDecoration() {
    return Stack(
      children: [
        Positioned(
          top: -80, right: -80,
          child: _Circle(size: 280, color: Colors.white.withValues(alpha: 0.04)),
        ),
        Positioned(
          top: 60, right: -30,
          child: _Circle(size: 140, color: Colors.white.withValues(alpha: 0.06)),
        ),
        Positioned(
          bottom: -100, left: -60,
          child: _Circle(size: 320, color: Colors.white.withValues(alpha: 0.04)),
        ),
        Positioned(
          bottom: 80, left: -20,
          child: _Circle(size: 120, color: const Color(0xFFE31E24).withValues(alpha: 0.15)),
        ),
        Positioned(
          top: MediaQuery.of(context).size.height * 0.55,
          right: 30,
          child: _Circle(size: 60, color: Colors.white.withValues(alpha: 0.08)),
        ),
      ],
    );
  }

  Widget _buildLogo() {
    return AnimatedBuilder(
      animation: Listenable.merge([_logoController, _pulseController]),
      builder: (_, __) {
        return Opacity(
          opacity: _logoOpacity.value,
          child: Transform.scale(
            scale: _logoScale.value,
            child: Transform.scale(
              scale: _pulse.value,
              child: Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(38),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.30),
                      blurRadius: 40,
                      offset: const Offset(0, 12),
                    ),
                    BoxShadow(
                      color: const Color(0xFFE31E24).withValues(alpha: 0.20),
                      blurRadius: 60,
                      spreadRadius: -10,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(36),
                  child: Image.asset(
                    'logo/logo.png',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(Icons.wifi, color: Colors.white, size: 72),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildText() {
    return AnimatedBuilder(
      animation: _textController,
      builder: (_, __) {
        return SlideTransition(
          position: _textSlide,
          child: Opacity(
            opacity: _textOpacity.value,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  child: const Text(
                    'منصة إدارة شبكات الواي فاي',
                    style: TextStyle(color: Colors.white70, fontSize: 13, letterSpacing: 0.5),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (i) => _Dot(delay: i * 200)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomBar() {
    return Positioned(
      bottom: 32,
      left: 0, right: 0,
      child: AnimatedBuilder(
        animation: _textController,
        builder: (_, __) => Opacity(
          opacity: _textOpacity.value,
          child: Column(
            children: [
              const Text(
                'Powered by SaiberWifi.net',
                style: TextStyle(color: Colors.white38, fontSize: 11),
                textDirection: TextDirection.ltr,
              ),
              const SizedBox(height: 4),
              Container(
                width: 40, height: 2,
                decoration: BoxDecoration(
                  color: const Color(0xFFE31E24),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Circle extends StatelessWidget {
  final double size;
  final Color color;
  const _Circle({required this.size, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: size, height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );
}

class _Dot extends StatefulWidget {
  final int delay;
  const _Dot({required this.delay});
  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut).drive(Tween(begin: 0.3, end: 1.0));
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: FadeTransition(
        opacity: _anim,
        child: Container(
          width: 6, height: 6,
          decoration: const BoxDecoration(
            color: Colors.white60,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
