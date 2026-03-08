// lib/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/app_state.dart';
import '../services/api_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _urlCtrl;
  late double _threshold;
  late bool _alertsEnabled;
  bool _saving = false;
  bool _testing = false;
  bool? _testResult;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    _urlCtrl = TextEditingController(text: s.serverUrl);
    _threshold = s.alertThreshold;
    _alertsEnabled = s.alertsEnabled;
  }

  @override
  void dispose() { _urlCtrl.dispose(); super.dispose(); }

  Future<void> _testConnection() async {
    setState(() { _testing = true; _testResult = null; });
    final api = ApiService(baseUrl: _urlCtrl.text.trim());
    final ok = await api.checkHealth();
    if (mounted) setState(() { _testing = false; _testResult = ok; });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await context.read<AppState>().saveSettings(
      url: _urlCtrl.text.trim(),
      threshold: _threshold,
      alertsOn: _alertsEnabled,
    );
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved'),
            backgroundColor: AppColors.green));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg0,
      appBar: AppBar(title: const Text('CONFIGURATION')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── Connection ───────────────────────────────────────────────
          const SectionHeader(title: 'CONNECTION',
              subtitle: 'FastAPI backend server URL'),
          const SizedBox(height: 12),
          CyberCard(
            child: Column(children: [
              TextField(
                controller: _urlCtrl,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'BACKEND URL',
                  prefixIcon: Icon(Icons.dns_outlined, size: 18),
                  hintText: 'http://10.0.2.2:8000',
                ),
              ),
              const SizedBox(height: 8),
              // Android hint
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.cyan.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.cyan.withValues(alpha: 0.2))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                  Text('📱 Android URL Guide',
                      style: TextStyle(color: AppColors.cyan, fontSize: 11,
                          fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  SizedBox(height: 4),
                  Text('• Emulator → http://10.0.2.2:8000',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                  Text('• Real device (same WiFi) → http://192.168.x.x:8000',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                  Text('• Get your PC IP: run  ipconfig (Win) or  ifconfig (Mac/Linux)',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
                ]),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _testing ? null : _testConnection,
                    icon: _testing
                        ? const SizedBox(width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.cyan))
                        : const Icon(Icons.wifi_tethering, size: 16),
                    label: const Text('TEST CONNECTION'),
                  ),
                ),
                if (_testResult != null) ...[
                  const SizedBox(width: 12),
                  Icon(
                    _testResult! ? Icons.check_circle : Icons.error,
                    color: _testResult! ? AppColors.green : AppColors.red,
                    size: 20),
                  const SizedBox(width: 6),
                  Text(_testResult! ? 'ONLINE' : 'OFFLINE',
                      style: TextStyle(
                        color: _testResult! ? AppColors.green : AppColors.red,
                        fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ]),
            ]),
          ),
          const SizedBox(height: 20),

          // ── Alert Settings ───────────────────────────────────────────
          const SectionHeader(title: 'ALERT SETTINGS',
              subtitle: 'Configure when alerts fire'),
          const SizedBox(height: 12),
          CyberCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Expanded(child: Text('ENABLE ALERTS',
                    style: TextStyle(color: AppColors.textSecondary,
                        fontSize: 12, letterSpacing: 1))),
                Switch(
                  value: _alertsEnabled,
                  onChanged: (v) => setState(() => _alertsEnabled = v)),
              ]),
              const Divider(height: 20),
              Row(children: [
                const Text('ALERT THRESHOLD',
                    style: TextStyle(color: AppColors.textSecondary,
                        fontSize: 12, letterSpacing: 1)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.scoreToColor(_threshold).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.scoreToColor(_threshold).withValues(alpha: 0.35))),
                  child: Text(
                    _threshold.toStringAsFixed(0),
                    style: TextStyle(color: AppColors.scoreToColor(_threshold),
                        fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ]),
              Slider(
                value: _threshold, min: 10, max: 100, divisions: 90,
                onChanged: (v) => setState(() => _threshold = v),
              ),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                for (final t in ['10\nLOW', '50\nMED', '75\nHIGH', '90\nCRIT'])
                  Text(t, style: const TextStyle(color: AppColors.textMuted,
                      fontSize: 9, letterSpacing: 1), textAlign: TextAlign.center),
              ]),
            ]),
          ),
          const SizedBox(height: 20),

          // ── Model Info ───────────────────────────────────────────────
          const SectionHeader(title: 'ML MODEL INFO'),
          const SizedBox(height: 12),
          CyberCard(
            child: Column(children: [
              for (final item in [
                ['Classifier', 'XGBoost (200 trees, depth=6)'],
                ['Anomaly Detector', 'K-Means (K=8 clusters)'],
                ['Prediction', 'EWMA α=0.3 + OLS trend'],
                ['Features', '20 dimensions per packet'],
                ['Training data', '15,000 synthetic samples'],
                ['Database', 'SQLite (dev) / PostgreSQL (prod)'],
              ]) _InfoRow(label: item[0], value: item[1]),
            ]),
          ),
          const SizedBox(height: 24),

          // ── Save & Logout ────────────────────────────────────────────
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.bg0))
                    : const Icon(Icons.save_outlined, size: 16),
                label: const Text('SAVE SETTINGS'),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () {
                showDialog(context: context, builder: (_) => AlertDialog(
                  backgroundColor: AppColors.bg1,
                  title: const Text('Logout?',
                      style: TextStyle(color: AppColors.textPrimary)),
                  content: const Text('You will be returned to the login screen.',
                      style: TextStyle(color: AppColors.textSecondary)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('CANCEL',
                          style: TextStyle(color: AppColors.textMuted))),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        context.read<AppState>().logout();
                      },
                      child: const Text('LOGOUT',
                          style: TextStyle(color: AppColors.red))),
                  ],
                ));
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.red,
                side: const BorderSide(color: AppColors.red)),
              icon: const Icon(Icons.logout, size: 16),
              label: const Text('LOGOUT'),
            ),
          ]),
          const SizedBox(height: 32),
        ]),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const Spacer(),
          Flexible(child: Text(value,
              style: const TextStyle(color: AppColors.cyan, fontSize: 11,
                  fontWeight: FontWeight.w600),
              textAlign: TextAlign.right)),
        ]),
      ),
      const Divider(height: 1),
    ]);
  }
}
