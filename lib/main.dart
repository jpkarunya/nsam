// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'providers/app_state.dart';
import 'services/api_service.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/live_scan_screen.dart';
import 'screens/threat_logs_screen.dart';
import 'screens/settings_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Lock orientation to portrait on phones, allow all on tablets/desktop
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
        ProxyProvider<AppState, ApiService>(
          update: (_, state, __) => ApiService(baseUrl: state.serverUrl),
        ),
      ],
      child: const NetGuardApp(),
    ),
  );
}

class NetGuardApp extends StatelessWidget {
  const NetGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NetGuard',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: Consumer<AppState>(
        builder: (_, state, __) =>
            state.isAuthenticated ? const AppShell() : const LoginScreen(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AppShell — handles both mobile (BottomNav) and wide screen (NavigationRail)
// ─────────────────────────────────────────────────────────────────────────────

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  static const _screens = [
    DashboardScreen(),
    LiveScanScreen(),
    ThreatLogsScreen(),
    SettingsScreen(),
  ];

  static const _navItems = [
    _NavItem(icon: Icons.dashboard_outlined, activeIcon: Icons.dashboard, label: 'DASH'),
    _NavItem(icon: Icons.radar_outlined, activeIcon: Icons.radar, label: 'SCAN'),
    _NavItem(icon: Icons.history_outlined, activeIcon: Icons.history, label: 'LOGS'),
    _NavItem(icon: Icons.settings_outlined, activeIcon: Icons.settings, label: 'CFG'),
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 720; // tablet / desktop

    if (isWide) {
      return _WideLayout(
          screens: _screens, items: _navItems,
          index: state.tabIndex, onTap: state.setTab,
          scanRunning: state.scanRunning);
    }
    return _MobileLayout(
        screens: _screens, items: _navItems,
        index: state.tabIndex, onTap: state.setTab);
  }
}

// Mobile: BottomNavigationBar ─────────────────────────────────────────────────

class _MobileLayout extends StatelessWidget {
  final List<Widget> screens;
  final List<_NavItem> items;
  final int index;
  final ValueChanged<int> onTap;

  const _MobileLayout({
    required this.screens, required this.items,
    required this.index, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg0,
      body: IndexedStack(index: index, children: screens),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.bg1,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: BottomNavigationBar(
          currentIndex: index,
          onTap: onTap,
          backgroundColor: Colors.transparent,
          elevation: 0,
          items: items.map((i) => BottomNavigationBarItem(
            icon: Icon(i.icon),
            activeIcon: Icon(i.activeIcon),
            label: i.label,
          )).toList(),
        ),
      ),
    );
  }
}

// Wide: NavigationRail ────────────────────────────────────────────────────────

class _WideLayout extends StatelessWidget {
  final List<Widget> screens;
  final List<_NavItem> items;
  final int index;
  final ValueChanged<int> onTap;
  final bool scanRunning;

  const _WideLayout({
    required this.screens, required this.items,
    required this.index, required this.onTap,
    required this.scanRunning,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg0,
      body: Row(children: [
        // Rail
        Container(
          width: 72,
          decoration: const BoxDecoration(
            color: AppColors.bg1,
            border: Border(right: BorderSide(color: AppColors.border))),
          child: Column(children: [
            const SizedBox(height: 16),
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: AppColors.cyan.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.cyan.withValues(alpha: 0.4))),
              child: const Icon(Icons.shield, color: AppColors.cyan, size: 20)),
            const SizedBox(height: 4),
            const Text('NG', style: TextStyle(color: AppColors.cyan,
                fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 2)),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Expanded(
              child: NavigationRail(
                selectedIndex: index,
                onDestinationSelected: onTap,
                labelType: NavigationRailLabelType.selected,
                backgroundColor: Colors.transparent,
                selectedIconTheme: const IconThemeData(color: AppColors.cyan),
                unselectedIconTheme: const IconThemeData(color: AppColors.textMuted),
                selectedLabelTextStyle: const TextStyle(
                    color: AppColors.cyan, fontSize: 9, letterSpacing: 1),
                unselectedLabelTextStyle: const TextStyle(
                    color: AppColors.textMuted, fontSize: 9),
                indicatorColor: AppColors.cyan.withValues(alpha: 0.1),
                destinations: items.map((i) => NavigationRailDestination(
                  icon: Icon(i.icon),
                  selectedIcon: Icon(i.activeIcon),
                  label: Text(i.label),
                )).toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(children: [
                LivePulseDot(active: scanRunning),
                const SizedBox(height: 4),
                Text(scanRunning ? 'LIVE' : 'IDLE',
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 8, letterSpacing: 1)),
              ]),
            ),
          ]),
        ),
        // Content
        Expanded(child: IndexedStack(index: index, children: screens)),
      ]),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavItem({required this.icon, required this.activeIcon, required this.label});
}
