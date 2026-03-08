// lib/screens/threat_logs_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';

class ThreatLogsScreen extends StatefulWidget {
  const ThreatLogsScreen({super.key});
  @override
  State<ThreatLogsScreen> createState() => _ThreatLogsScreenState();
}

class _ThreatLogsScreenState extends State<ThreatLogsScreen> {
  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;
  int _total = 0;
  String? _filterSeverity;
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    // infinite scroll: load more when near bottom
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      if (!_loading && _logs.length < _total) {
        _loadMore();
      }
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await context.read<ApiService>().getLogs(
        limit: 50, offset: 0, severity: _filterSeverity);
      if (mounted) setState(() {
        _logs = (data['logs'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        _total = (data['total'] as num?)?.toInt() ?? 0;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Future<void> _loadMore() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final data = await context.read<ApiService>().getLogs(
        limit: 50, offset: _logs.length, severity: _filterSeverity);
      final more = (data['logs'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (mounted) setState(() { _logs.addAll(more); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg0,
      appBar: AppBar(
        title: const Text('THREAT LOGS'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: _FilterBar(
            selected: _filterSeverity,
            onChanged: (v) {
              setState(() => _filterSeverity = v);
              _load();
            },
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(
              child: Text('$_total EVENTS',
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 10, letterSpacing: 1)),
            ),
          ),
          IconButton(icon: const Icon(Icons.refresh, size: 18), onPressed: _load),
        ],
      ),
      body: _loading && _logs.isEmpty
          ? const Center(child: CircularProgressIndicator(color: AppColors.cyan))
          : _logs.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.history, color: AppColors.textMuted.withValues(alpha: 0.4), size: 52),
                  const SizedBox(height: 14),
                  const Text('No threat events logged yet',
                      style: TextStyle(color: AppColors.textMuted)),
                  const SizedBox(height: 6),
                  const Text('Start a scan to generate logs',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                ]))
              : RefreshIndicator(
                  color: AppColors.cyan, onRefresh: _load,
                  child: ListView.builder(
                    controller: _scrollCtrl,
                    itemCount: _logs.length + (_loading ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i >= _logs.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator(
                              color: AppColors.cyan, strokeWidth: 2)));
                      }
                      return _LogCard(log: _logs[i]);
                    },
                  ),
                ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final String? selected;
  final ValueChanged<String?> onChanged;
  const _FilterBar({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final opts = <String?>[null, 'LOW', 'MEDIUM', 'HIGH', 'CRITICAL'];
    return Container(
      height: 48,
      color: AppColors.bg1,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: ListView(scrollDirection: Axis.horizontal, children: opts.map((s) {
        final isSelected = selected == s;
        final color = s == null ? AppColors.cyan : AppColors.severityColor(s);
        return GestureDetector(
          onTap: () => onChanged(s),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: isSelected ? color.withValues(alpha: 0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected ? color.withValues(alpha: 0.6) : AppColors.border)),
            child: Text(s ?? 'ALL',
                style: TextStyle(color: isSelected ? color : AppColors.textMuted,
                    fontSize: 11, letterSpacing: 1,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
          ),
        );
      }).toList()),
    );
  }
}

class _LogCard extends StatelessWidget {
  final Map<String, dynamic> log;
  const _LogCard({required this.log});

  @override
  Widget build(BuildContext context) {
    final severity = log['severity'] as String? ?? 'LOW';
    final label = log['threat_label'] as String? ?? 'Normal';
    final score = (log['threat_score'] as num?)?.toDouble() ?? 0.0;
    final color = AppColors.severityColor(severity);
    final isAnomaly = log['is_anomaly'] as bool? ?? false;
    final ts = DateTime.fromMillisecondsSinceEpoch(
        ((log['timestamp'] as num?) ?? 0).toInt() * 1000).toLocal();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.bg1,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color:
            severity == 'CRITICAL' ? AppColors.red.withValues(alpha: 0.3) : AppColors.border)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Top row: timestamp, severity, score
          Row(children: [
            Text(
              '${ts.year}-${ts.month.toString().padLeft(2,'0')}-${ts.day.toString().padLeft(2,'0')} '
              '${ts.hour.toString().padLeft(2,'0')}:${ts.minute.toString().padLeft(2,'0')}:${ts.second.toString().padLeft(2,'0')}',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 10,
                  fontFamily: 'monospace')),
            const Spacer(),
            SeverityChip(severity: severity),
            const SizedBox(width: 8),
            Text(score.toStringAsFixed(1),
                style: TextStyle(color: color, fontSize: 16,
                    fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 8),
          // Middle row: src → dst, protocol
          Row(children: [
            Icon(Icons.computer_outlined, color: AppColors.textMuted, size: 13),
            const SizedBox(width: 5),
            Flexible(child: Text(log['src_ip'] as String? ?? '—',
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 12,
                    fontFamily: 'monospace'))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.arrow_forward, color: AppColors.textMuted, size: 12)),
            Flexible(child: Text(log['dst_ip'] as String? ?? '—',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12,
                    fontFamily: 'monospace'))),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.bg3, borderRadius: BorderRadius.circular(4)),
              child: Text(log['protocol'] as String? ?? '?',
                  style: const TextStyle(color: AppColors.cyan, fontSize: 10,
                      letterSpacing: 1))),
          ]),
          const SizedBox(height: 8),
          // Bottom row: classification, anomaly, conn freq
          Row(children: [
            ThreatChip(label: label),
            const SizedBox(width: 8),
            if (isAnomaly)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.purple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.purple.withValues(alpha: 0.3))),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.warning_amber, color: AppColors.purple, size: 10),
                  SizedBox(width: 4),
                  Text('ANOMALY', style: TextStyle(color: AppColors.purple,
                      fontSize: 9, letterSpacing: 1)),
                ])),
            const Spacer(),
            Text('${log['packet_length'] ?? 0}B  •  ${log['protocol'] ?? '?'}:${log['dst_port'] ?? 0}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
          ]),
        ]),
      ),
    );
  }
}
