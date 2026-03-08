// lib/theme/app_theme.dart — Flutter 3.41 compatible
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const Color bg0 = Color(0xFF050B14);
  static const Color bg1 = Color(0xFF0A1628);
  static const Color bg2 = Color(0xFF0F1E38);
  static const Color bg3 = Color(0xFF152540);
  static const Color cyan = Color(0xFF00E5FF);
  static const Color green = Color(0xFF00FF88);
  static const Color yellow = Color(0xFFFFB800);
  static const Color orange = Color(0xFFFF6B00);
  static const Color red = Color(0xFFFF3366);
  static const Color purple = Color(0xFF7C4DFF);
  static const Color textPrimary = Color(0xFFE8F4FD);
  static const Color textSecondary = Color(0xFF7A9CC0);
  static const Color textMuted = Color(0xFF3D5A7A);
  static const Color border = Color(0xFF1A3A5C);

  static Color severityColor(String severity) {
    switch (severity.toUpperCase()) {
      case 'LOW':      return green;
      case 'MEDIUM':   return yellow;
      case 'HIGH':     return orange;
      case 'CRITICAL': return red;
      default:         return cyan;
    }
  }

  static Color scoreToColor(double score) {
    if (score < 25) return green;
    if (score < 50) return yellow;
    if (score < 75) return orange;
    return red;
  }

  static String scoreToSeverity(double score) {
    if (score < 25) return 'LOW';
    if (score < 50) return 'MEDIUM';
    if (score < 75) return 'HIGH';
    return 'CRITICAL';
  }
}

// Safe opacity helper — avoids deprecated .withOpacity()
Color _ao(Color c, double opacity) =>
    Color.fromRGBO(c.r.toInt(), c.g.toInt(), c.b.toInt(), opacity);

class AppTheme {
  static ThemeData get dark {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.bg1,
      systemNavigationBarIconBrightness: Brightness.light,
    ));

    final base = GoogleFonts.spaceMonoTextTheme(ThemeData.dark().textTheme);

    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.bg0,
      primaryColor: AppColors.cyan,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.cyan,
        secondary: AppColors.purple,
        surface: AppColors.bg1,
        error: AppColors.red,
        onPrimary: AppColors.bg0,
        onSurface: AppColors.textPrimary,
      ),
      textTheme: base.copyWith(
        displayLarge: base.displayLarge?.copyWith(
            color: AppColors.textPrimary, fontSize: 28,
            fontWeight: FontWeight.bold, letterSpacing: 2),
        displayMedium: base.displayMedium?.copyWith(
            color: AppColors.textPrimary, fontSize: 22,
            fontWeight: FontWeight.bold, letterSpacing: 1.5),
        titleLarge: base.titleLarge?.copyWith(
            color: AppColors.textPrimary, fontSize: 16,
            fontWeight: FontWeight.w600, letterSpacing: 1),
        titleMedium: base.titleMedium?.copyWith(
            color: AppColors.textSecondary, fontSize: 13),
        bodyLarge: base.bodyLarge?.copyWith(
            color: AppColors.textPrimary, fontSize: 13),
        bodyMedium: base.bodyMedium?.copyWith(
            color: AppColors.textSecondary, fontSize: 12),
        labelSmall: base.labelSmall?.copyWith(
            color: AppColors.textMuted, fontSize: 10, letterSpacing: 1.5),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.bg1,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.spaceMono(
            color: AppColors.cyan, fontSize: 15,
            fontWeight: FontWeight.bold, letterSpacing: 2),
        iconTheme: const IconThemeData(color: AppColors.cyan),
        actionsIconTheme: const IconThemeData(color: AppColors.textSecondary),
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      // FIXED: CardThemeData (not CardTheme) for Flutter 3.27+
      cardTheme: CardThemeData(
        color: AppColors.bg1,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.bg1,
        selectedItemColor: AppColors.cyan,
        unselectedItemColor: AppColors.textMuted,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        selectedLabelStyle: TextStyle(fontSize: 9, letterSpacing: 1),
        unselectedLabelStyle: TextStyle(fontSize: 9),
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.cyan,
          foregroundColor: AppColors.bg0,
          textStyle: GoogleFonts.spaceMono(
              fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.cyan,
          side: const BorderSide(color: AppColors.cyan),
          textStyle: GoogleFonts.spaceMono(fontSize: 12, letterSpacing: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bg2,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.cyan, width: 1.5)),
        labelStyle: GoogleFonts.spaceMono(
            color: AppColors.textSecondary, fontSize: 11, letterSpacing: 1),
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
        prefixIconColor: AppColors.textSecondary,
        suffixIconColor: AppColors.textMuted,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1),
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.cyan,
        inactiveTrackColor: AppColors.bg3,
        thumbColor: AppColors.cyan,
        overlayColor: Color(0x2200E5FF),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? AppColors.cyan
                : AppColors.textMuted),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? const Color(0x4D00E5FF)
                : AppColors.bg3),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.bg2,
        contentTextStyle: GoogleFonts.spaceMono(
            color: AppColors.textPrimary, fontSize: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Shared Widgets
// ─────────────────────────────────────────────────────────────

class CyberCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final Color? borderColor;
  final bool glowEffect;
  final VoidCallback? onTap;

  const CyberCard({
    super.key,
    required this.child,
    this.padding,
    this.borderColor,
    this.glowEffect = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bc = borderColor ?? AppColors.border;
    final gc = borderColor ?? AppColors.cyan;
    final container = Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bg1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: bc),
        boxShadow: glowEffect
            ? [BoxShadow(color: _ao(gc, 0.18), blurRadius: 18, spreadRadius: 1)]
            : null,
      ),
      child: child,
    );
    if (onTap != null) return GestureDetector(onTap: onTap, child: container);
    return container;
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Color? accentColor;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? AppColors.cyan;
    return Row(children: [
      Container(
        width: 3, height: 16,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
          boxShadow: [BoxShadow(color: _ao(color, 0.5), blurRadius: 8)],
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(letterSpacing: 1.5, fontSize: 13)),
          if (subtitle != null)
            Text(subtitle!,
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: 10, letterSpacing: 1)),
        ]),
      ),
      if (trailing != null) trailing!,
    ]);
  }
}

class ThreatChip extends StatelessWidget {
  final String label;
  const ThreatChip({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final color = label == 'Normal'
        ? AppColors.green
        : label == 'Suspicious'
            ? AppColors.yellow
            : AppColors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _ao(color, 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _ao(color, 0.35)),
      ),
      child: Text(label.toUpperCase(),
          style: TextStyle(
              color: color, fontSize: 9,
              letterSpacing: 1, fontWeight: FontWeight.bold)),
    );
  }
}

class SeverityChip extends StatelessWidget {
  final String severity;
  const SeverityChip({super.key, required this.severity});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.severityColor(severity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _ao(color, 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _ao(color, 0.35)),
      ),
      child: Text(severity.toUpperCase(),
          style: TextStyle(
              color: color, fontSize: 9,
              letterSpacing: 1, fontWeight: FontWeight.bold)),
    );
  }
}

class LivePulseDot extends StatefulWidget {
  final bool active;
  final Color? color;
  const LivePulseDot({super.key, required this.active, this.color});
  @override
  State<LivePulseDot> createState() => _LivePulseDotState();
}

class _LivePulseDotState extends State<LivePulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat(reverse: true);

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final col = widget.color ?? AppColors.green;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Container(
        width: 8, height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.active ? col : AppColors.textMuted,
          boxShadow: widget.active
              ? [BoxShadow(color: _ao(col, _c.value * 0.7), blurRadius: 10)]
              : null,
        ),
      ),
    );
  }
}
