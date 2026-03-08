// lib/screens/live_scan_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/app_state.dart';
import '../services/api_service.dart';

class LiveScanScreen extends StatefulWidget {
  const LiveScanScreen({super.key});
  @override
  State<LiveScanScreen> createState() => _LiveScanScreenState();
}

class _LiveScanScreenState extends State<LiveScanScreen> {
  bool _scanning = false;
  bool _starting = false;
  final List<Map<String, dynamic>> _feed = [];
  Timer? _pollTimer;
  final _scrollCtrl = ScrollController();
  String _interface = '';
  int _packetsTotal = 0;
  int _threatsFound = 0;
  double _avgScore = 0.0;

  @override
  void dispose() {
    _pollTimer?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _startScan() async {
    setState(() => _starting = true);
    try {
      final api = context.read<ApiService>();
      await api.startScan(interface: _interface.trim().isEmpty ? null : _interface.trim());
      if (mounted) {
        setState(() { _scanning = true; _feed.clear(); _starting = false; });
        context.read<AppState>().setScanRunning(true);
        _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
      }
    } catch (e) {
      if (mounted) {
        setState(() => _starting = false);
        _snack('Could not start scan: $e', AppColors.red);
      }
    }
  }

  Future<void> _stopScan() async {
    _pollTimer?.cancel();
    try { await context.read<ApiService>().stopScan(); } catch (_) {}
    if (mounted) {
      setState(() => _scanning = false);
      context.read<AppState>().setScanRunning(false);
    }
  }

  Future<void> _poll() async {
    if (!_scanning) return;
    try {
      final api = context.read<ApiService>();
      final status = await api.getScanStatus(maxPackets: 20);
      final packets = (status['packets'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (packets.isEmpty) return;

      // Run threat detection
      final detect = await api.detectThreats(packets);
      final results = (detect['results'] as List?)?.cast<Map>() ?? [];
      final agg = (detect['aggregate_threat_score'] as num?)?.toDouble() ?? 0.0;

      if (!mounted) return;
      setState(() {
        for (int i = 0; i < packets.length; i++) {
          final r = i < results.length ? results[i] : <String, dynamic>{};
          _feed.insert(0, {
            ...packets[i],
            'threat_label': r['threat_label'] ?? 'Normal',
            'threat_score': r['threat_score'] ?? 0.0,
            'severity': r['severity'] ?? 'LOW',
            'is_anomaly': r['is_anomaly'] ?? false,
          });
        }
        _packetsTotal += packets.length;
        _threatsFound += results.where((r) => r['threat_label'] != 'Normal').length;
        _avgScore = agg;
        if (_feed.length > 200) _feed.removeRange(200, _feed.length);
      });
    } catch (_) {}
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color,
          duration: const Duration(seconds: 3)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg0,
      appBar: AppBar(
        title: const Text('LIVE SCAN'),
        actions: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            LivePulseDot(active: _scanning, color: _scanning ? AppColors.green : AppColors.textMuted),
            const SizedBox(width: 6),
            Text(_scanning ? 'SCANNING' : 'IDLE',
                style: TextStyle(
                  color: _scanning ? AppColors.green : AppColors.textMuted,
                  fontSize: 10, letterSpacing: 1.5)),
            const SizedBox(width: 14),
          ]),
        ],
      ),
      body: Column(children: [
        // ── Controls ────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          color: AppColors.bg1,
          child: Column(children: [
            Row(children: [
              Expanded(
                child: TextField(
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                  enabled: !_scanning,
                  decoration: const InputDecoration(
                    labelText: 'INTERFACE',
                    hintText: 'eth0 / en0 / blank = auto',
                    prefixIcon: Icon(Icons.cable_outlined, size: 18),
                    isDense: true,
                  ),
                  onChanged: (v) => _interface = v,
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _starting ? null : (_scanning ? _stopScan : _startScan),
                icon: _starting
                    ? const SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.bg0))
                    : Icon(_scanning ? Icons.stop : Icons.play_arrow, size: 18),
                label: Text(_scanning ? 'STOP' : 'START'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _scanning ? AppColors.red : AppColors.cyan,
                  foregroundColor: AppColors.bg0,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              _MiniStat('PACKETS', _packetsTotal.toString(), AppColors.cyan),
              const SizedBox(width: 8),
              _MiniStat('THREATS', _threatsFound.toString(), AppColors.red),
              const SizedBox(width: 8),
              _MiniStat('AVG SCORE', _avgScore.toStringAsFixed(1), AppColors.yellow),
            ]),
          ]),
        ),

        // ── Feed header ─────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          color: AppColors.bg2,
          child: Row(children: [
            const Text('ACTIVITY FEED', style: TextStyle(
                color: AppColors.textMuted, fontSize: 10, letterSpacing: 2)),
            const Spacer(),
            Text('${_feed.length} events',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
          ]),
        ),

        // ── Feed list ───────────────────────────────────────────────────
        Expanded(
          child: _feed.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.radar, color: AppColors.textMuted.withValues(alpha: 0.5), size: 52),
                  const SizedBox(height: 14),
                  Text(
                    _scanning ? 'Waiting for packets...' : 'Tap START to begin scanning',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                  if (!_scanning) ...[
                    const SizedBox(height: 6),
                    const Text('(Requires root/admin on the backend server)',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                  ],
                ]))
              : ListView.builder(
                  controller: _scrollCtrl,
                  itemCount: _feed.length,
                  itemBuilder: (_, i) => _FeedRow(packet: _feed[i]),
                ),
        ),
      ]),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _MiniStat(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.bg2, borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border)),
        child: Column(children: [
          Text(value, style: TextStyle(color: color, fontSize: 16,
              fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(color: AppColors.textMuted,
              fontSize: 8, letterSpacing: 1)),
        ]),
      ),
    );
  }
}

class _FeedRow extends StatelessWidget {
  final Map<String, dynamic> packet;
  const _FeedRow({required this.packet});

  @override
  Widget build(BuildContext context) {
    final label = packet['threat_label'] as String? ?? 'Normal';
    final score = (packet['threat_score'] as num?)?.toDouble() ?? 0.0;
    final sc = AppColors.scoreToColor(score);
    final ts = DateTime.fromMillisecondsSinceEpoch(
        ((packet['timestamp'] as num?) ?? 0).toInt() * 1000);
    final isAnomaly = packet['is_anomaly'] as bool? ?? false;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: label == 'Malicious' ? AppColors.red.withValues(alpha: 0.04) : Colors.transparent,
        border: const Border(bottom: BorderSide(color: AppColors.border, width: 0.5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Row 1: time, proto, score, threat chip
        Row(children: [
          Text(
            '${ts.hour.toString().padLeft(2,'0')}:${ts.minute.toString().padLeft(2,'0')}:${ts.second.toString().padLeft(2,'0')}',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 10,
                fontFamily: 'monospace')),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.bg3, borderRadius: BorderRadius.circular(3)),
            child: Text(packet['protocol'] as String? ?? '?',
                style: const TextStyle(color: AppColors.cyan, fontSize: 9,
                    letterSpacing: 1))),
          const Spacer(),
          if (isAnomaly)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(Icons.warning_amber, color: AppColors.purple, size: 13)),
          ThreatChip(label: label),
          const SizedBox(width: 8),
          Text(score.toStringAsFixed(1),
              style: TextStyle(color: sc, fontSize: 13,
                  fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 3),
        // Row 2: src → dst
        Row(children: [
          Text(packet['src_ip'] as String? ?? '—',
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 11,
                  fontFamily: 'monospace')),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text('→', style: TextStyle(color: AppColors.textMuted, fontSize: 10))),
          Text(packet['dst_ip'] as String? ?? '—',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11,
                  fontFamily: 'monospace')),
          const Spacer(),
          Text('${packet['packet_length'] ?? 0}B',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
        ]),
      ]),
    );
  }
}
