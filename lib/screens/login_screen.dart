// lib/screens/login_screen.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/app_state.dart';
import '../services/api_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _userCtrl = TextEditingController(text: 'admin');
  final _passCtrl = TextEditingController(text: 'netguard');
  final _userFocus = FocusNode();
  final _passFocus = FocusNode();
  bool _obscure = true;
  bool _loading = false;
  String? _error;
  bool _serverOnline = false;
  bool _checkingServer = true;
  Timer? _healthTimer;

  late final AnimationController _fadeCtrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))
        ..forward();
  late final Animation<double> _fadeAnim =
      CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

  late final AnimationController _glowCtrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))
        ..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _checkHealth();
    _healthTimer = Timer.periodic(const Duration(seconds: 5), (_) => _checkHealth());
  }

  @override
  void dispose() {
    _healthTimer?.cancel();
    _fadeCtrl.dispose();
    _glowCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _userFocus.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  Future<void> _checkHealth() async {
    setState(() => _checkingServer = true);
    final api = context.read<ApiService>();
    final ok = await api.checkHealth();
    if (mounted) setState(() { _serverOnline = ok; _checkingServer = false; });
  }

  Future<void> _login() async {
    if (_userCtrl.text.isEmpty || _passCtrl.text.isEmpty) {
      setState(() => _error = 'Enter username and password');
      return;
    }
    setState(() { _loading = true; _error = null; });
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      context.read<AppState>().login();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg0,
      body: Stack(children: [
        // Animated grid background
        const _GridBackground(),
        // Centered card
        Center(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: AnimatedBuilder(
                  animation: _glowCtrl,
                  builder: (_, child) => Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: AppColors.bg1,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.cyan
                              .withValues(alpha: 0.05 + _glowCtrl.value * 0.06),
                          blurRadius: 60, spreadRadius: 10,
                        )
                      ],
                    ),
                    child: child!,
                  ),
                  child: _buildForm(),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildForm() {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      // Shield logo with pulsing border
      AnimatedBuilder(
        animation: _glowCtrl,
        builder: (_, __) => Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.cyan.withValues(alpha: 0.08),
            border: Border.all(
              color: AppColors.cyan.withValues(alpha: 0.3 + _glowCtrl.value * 0.5),
              width: 1.5),
            boxShadow: [BoxShadow(
              color: AppColors.cyan.withValues(alpha: _glowCtrl.value * 0.35),
              blurRadius: 24)],
          ),
          child: const Icon(Icons.shield_outlined, color: AppColors.cyan, size: 32),
        ),
      ),
      const SizedBox(height: 14),
      const Text('NETGUARD',
          style: TextStyle(color: AppColors.cyan, fontSize: 22,
              fontWeight: FontWeight.bold, letterSpacing: 6)),
      const SizedBox(height: 4),
      const Text('AI THREAT DETECTION SYSTEM',
          style: TextStyle(color: AppColors.textMuted, fontSize: 9,
              letterSpacing: 3)),
      const SizedBox(height: 24),

      // Server status badge
      AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: (_serverOnline ? AppColors.green : AppColors.red)
              .withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: (_serverOnline ? AppColors.green : AppColors.red)
                .withValues(alpha: 0.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _checkingServer
              ? SizedBox(width: 8, height: 8,
                  child: CircularProgressIndicator(strokeWidth: 1.5,
                    color: AppColors.textMuted))
              : LivePulseDot(
                  active: _serverOnline,
                  color: _serverOnline ? AppColors.green : AppColors.red),
          const SizedBox(width: 8),
          Text(
            _checkingServer
                ? 'CHECKING SERVER...'
                : 'BACKEND ${_serverOnline ? "ONLINE" : "OFFLINE"}',
            style: TextStyle(
              color: _serverOnline ? AppColors.green : AppColors.red,
              fontSize: 11, letterSpacing: 1.5, fontWeight: FontWeight.bold,
            ),
          ),
        ]),
      ),
      const SizedBox(height: 28),

      // Username
      TextField(
        controller: _userCtrl,
        focusNode: _userFocus,
        autofocus: false,   // prevents DOM assertion on Flutter web
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
        textInputAction: TextInputAction.next,
        onSubmitted: (_) => _passFocus.requestFocus(),
        decoration: const InputDecoration(
          labelText: 'USERNAME',
          prefixIcon: Icon(Icons.person_outline, size: 18)),
      ),
      const SizedBox(height: 14),

      // Password
      TextField(
        controller: _passCtrl,
        focusNode: _passFocus,
        autofocus: false,
        obscureText: _obscure,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _login(),
        decoration: InputDecoration(
          labelText: 'PASSWORD',
          prefixIcon: const Icon(Icons.lock_outline, size: 18),
          suffixIcon: IconButton(
            icon: Icon(
              _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              size: 18, color: AppColors.textMuted),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
      ),

      // Error
      if (_error != null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.red.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.red.withValues(alpha: 0.3))),
          child: Row(children: [
            const Icon(Icons.error_outline, color: AppColors.red, size: 15),
            const SizedBox(width: 8),
            Expanded(child: Text(_error!,
                style: const TextStyle(color: AppColors.red, fontSize: 12))),
          ]),
        ),
      ],
      const SizedBox(height: 24),

      // Login button
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _loading ? null : _login,
          child: _loading
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.bg0))
              : const Text('AUTHENTICATE'),
        ),
      ),
      const SizedBox(height: 16),

      // Hint: offline mode
      if (!_serverOnline)
        TextButton(
          onPressed: () => context.read<AppState>().login(),
          child: const Text('Continue in Demo Mode (no backend)',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
        ),

      const SizedBox(height: 8),
      const Text('v1.0.0 — AI Cybersecurity Project',
          style: TextStyle(color: AppColors.textMuted, fontSize: 10),
          textAlign: TextAlign.center),
    ]);
  }
}

// Animated grid background painter
class _GridBackground extends StatefulWidget {
  const _GridBackground();
  @override
  State<_GridBackground> createState() => _GridBackgroundState();
}

class _GridBackgroundState extends State<_GridBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 8))
        ..repeat();
  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => CustomPaint(
        size: MediaQuery.of(context).size,
        painter: _GridPainter(_c.value),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  final double t;
  _GridPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFF0A2040).withValues(alpha: 0.6)
      ..strokeWidth = 0.5;
    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
    // Animated scan line
    final scanY = (size.height * t) % size.height;
    final scanPaint = Paint()
      ..shader = LinearGradient(colors: [
        Colors.transparent,
        AppColors.cyan.withValues(alpha: 0.12),
        Colors.transparent,
      ]).createShader(Rect.fromLTWH(0, scanY - 30, size.width, 60));
    canvas.drawRect(Rect.fromLTWH(0, scanY - 30, size.width, 60), scanPaint);

    // Random dim dots at grid intersections
    final dotP = Paint()..color = AppColors.cyan.withValues(alpha: 0.08);
    for (double x = 0; x < size.width; x += step) {
      for (double y = 0; y < size.height; y += step) {
        if ((x + y + t * 100).round() % 7 == 0) {
          canvas.drawCircle(Offset(x, y), 1.5, dotP);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.t != t;
}
