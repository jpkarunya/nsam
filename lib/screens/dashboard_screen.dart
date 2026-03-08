// lib/screens/dashboard_screen.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/app_state.dart';
import '../services/api_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _loading = true;
  String? _errorMsg;
  Timer? _timer;
  Map<String, dynamic> _data = {};

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  Future<void> _load() async {
    try {
      final data = await context.read<ApiService>().getDashboardData();
      if (mounted) {
        setState(() { _data = data; _loading = false; _errorMsg = null; });
        context.read<AppState>().updateDashData(data);
      }
    } catch (e) {
      if (mounted) setState(() { _errorMsg = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final alerts = context.watch<AppState>().alerts;
    return Scaffold(
      backgroundColor: AppColors.bg0,
      appBar: _buildAppBar(),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.cyan))
          : RefreshIndicator(
              color: AppColors.cyan, onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(14),
                child: Column(children: [
                  // Alert banners
                  ...alerts.take(2).toList().asMap().entries.map(
                    (e) => _AlertBanner(
                      alert: e.value,
                      onDismiss: () => context.read<AppState>().dismissAlert(e.key),
                    )),
                  // Server error banner
                  if (_errorMsg != null) _ErrorBanner(message: _errorMsg!),
                  // Main content
                  _buildContent(),
                ]),
              ),
            ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final state = context.watch<AppState>();
    return AppBar(
      title: const Text('THREAT DASHBOARD'),
      actions: [
        LivePulseDot(active: _errorMsg == null),
        const SizedBox(width: 6),
        Text(
          _errorMsg == null ? 'LIVE' : 'ERROR',
          style: TextStyle(
            color: _errorMsg == null ? AppColors.green : AppColors.red,
            fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 12),
        IconButton(icon: const Icon(Icons.refresh, size: 18), onPressed: _load),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildContent() {
    final score = (_data['current_threat_score'] as num?)?.toDouble() ?? 0.0;
    final severity = _data['severity'] as String? ?? 'LOW';
    final total = (_data['total_packets_analyzed'] as num?)?.toInt() ?? 0;
    final anomalies = (_data['anomaly_count'] as num?)?.toInt() ?? 0;
    final labels = (_data['label_distribution'] as Map?)?.cast<String, dynamic>() ?? {};
    final trend = (_data['trend_summary'] as Map?)?.cast<String, dynamic>() ?? {};
    final hourly = (_data['hourly_trend'] as List?)?.cast<Map>() ?? [];
    final preds = (_data['predictions'] as List?)?.cast<Map>() ?? [];
    final sources = (_data['top_threat_sources'] as List?)?.cast<Map>() ?? [];

    return Column(children: [
      // ── Threat Gauge (full-width on mobile) ──────────────────────
      _ThreatGaugeCard(score: score, severity: severity),
      const SizedBox(height: 12),

      // ── 2x2 Stats grid ───────────────────────────────────────────
      GridView.count(
        crossAxisCount: 2, shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 10, mainAxisSpacing: 10,
        childAspectRatio: 2.2,
        children: [
          _StatCard('PACKETS', total.toString(),
              Icons.analytics_outlined, AppColors.cyan),
          _StatCard('ANOMALIES', anomalies.toString(),
              Icons.warning_amber_outlined, AppColors.purple),
          _StatCard('MALICIOUS',
              (labels['Malicious'] ?? 0).toString(),
              Icons.dangerous_outlined, AppColors.red),
          _StatCard('SUSPICIOUS',
              (labels['Suspicious'] ?? 0).toString(),
              Icons.help_outline, AppColors.yellow),
        ],
      ),
      const SizedBox(height: 12),

      // ── Risk Trend Chart ─────────────────────────────────────────
      _TrendCard(hourly: hourly, predictions: preds, trend: trend),
      const SizedBox(height: 12),

      // ── Traffic Distribution Pie ─────────────────────────────────
      _DistributionCard(labels: labels),
      const SizedBox(height: 12),

      // ── Top Threat Sources ───────────────────────────────────────
      if (sources.isNotEmpty) _TopSourcesCard(sources: sources),
      const SizedBox(height: 12),
    ]);
  }
}

// ── Alert banner ──────────────────────────────────────────────────────────────

class _AlertBanner extends StatelessWidget {
  final Map<String, dynamic> alert;
  final VoidCallback onDismiss;
  const _AlertBanner({required this.alert, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final score = (alert['score'] as num?)?.toDouble() ?? 0.0;
    final ts = alert['ts'] as DateTime?;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.45))),
      child: Row(children: [
        const Icon(Icons.warning_rounded, color: AppColors.red, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('⚡ THREAT ALERT — ${alert['severity']}',
              style: const TextStyle(color: AppColors.red, fontSize: 12,
                  fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          Text('Score: ${score.toStringAsFixed(1)}  •  ${ts?.toLocal().toString().substring(11, 19) ?? ""}',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        ])),
        IconButton(
          icon: const Icon(Icons.close, size: 16, color: AppColors.textMuted),
          onPressed: onDismiss, padding: EdgeInsets.zero,
          constraints: const BoxConstraints()),
      ]),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.orange.withValues(alpha: 0.35))),
      child: Row(children: [
        const Icon(Icons.cloud_off_outlined, color: AppColors.orange, size: 16),
        const SizedBox(width: 10),
        Expanded(child: Text('Backend offline — showing demo data',
            style: const TextStyle(color: AppColors.orange, fontSize: 12))),
      ]),
    );
  }
}

// ── Threat Gauge ──────────────────────────────────────────────────────────────

class _ThreatGaugeCard extends StatelessWidget {
  final double score;
  final String severity;
  const _ThreatGaugeCard({required this.score, required this.severity});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.scoreToColor(score);
    return CyberCard(
      borderColor: color.withValues(alpha: 0.3),
      glowEffect: score > 60,
      child: Column(children: [
        SectionHeader(title: 'THREAT LEVEL',
            trailing: SeverityChip(severity: severity)),
        const SizedBox(height: 12),
        SizedBox(
          height: 170,
          child: Stack(alignment: Alignment.center, children: [
            CustomPaint(
              size: const Size(double.infinity, 170),
              painter: _ArcGaugePainter(score: score, color: color)),
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(score.toStringAsFixed(1),
                    style: TextStyle(color: color, fontSize: 42,
                        fontWeight: FontWeight.bold, letterSpacing: -1)),
                Text('/ 100', style: TextStyle(color: color.withValues(alpha: 0.5),
                    fontSize: 13)),
                const SizedBox(height: 4),
                Text(severity, style: TextStyle(color: color, fontSize: 12,
                    letterSpacing: 4, fontWeight: FontWeight.bold)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          for (final s in ['LOW', 'MED', 'HIGH', 'CRIT'])
            Text(s, style: TextStyle(
              color: severity.startsWith(s.substring(0, 3))
                  ? AppColors.severityColor(severity) : AppColors.textMuted,
              fontSize: 9, letterSpacing: 1,
            )),
        ]),
      ]),
    );
  }
}

class _ArcGaugePainter extends CustomPainter {
  final double score;
  final Color color;
  const _ArcGaugePainter({required this.score, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.72;
    final r = min(size.width * 0.38, 100.0);
    const startAngle = pi * 0.75;
    const totalAngle = pi * 1.5;
    final sweep = (score / 100.0) * totalAngle;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);

    // Track
    canvas.drawArc(rect, startAngle, totalAngle, false,
        Paint()..color = AppColors.bg3..style = PaintingStyle.stroke
          ..strokeWidth = 14..strokeCap = StrokeCap.round);

    if (sweep > 0.01) {
      // Glow
      canvas.drawArc(rect, startAngle, sweep, false,
          Paint()..color = color.withValues(alpha: 0.25)..style = PaintingStyle.stroke
            ..strokeWidth = 24..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12));
      // Fill
      canvas.drawArc(rect, startAngle, sweep, false,
          Paint()..color = color..style = PaintingStyle.stroke
            ..strokeWidth = 14..strokeCap = StrokeCap.round);
    }

    // Tick marks at 25/50/75
    for (final pct in [0.25, 0.5, 0.75]) {
      final a = startAngle + totalAngle * pct;
      final inner = Offset(cx + (r - 16) * cos(a), cy + (r - 16) * sin(a));
      final outer = Offset(cx + (r + 4) * cos(a), cy + (r + 4) * sin(a));
      canvas.drawLine(inner, outer,
          Paint()..color = AppColors.border..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(_ArcGaugePainter o) => o.score != score || o.color != color;
}

// ── Stat Card ─────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _StatCard(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return CyberCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        Container(width: 34, height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 16)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: TextStyle(color: color, fontSize: 20,
              fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(color: AppColors.textMuted,
              fontSize: 9, letterSpacing: 1)),
        ])),
      ]),
    );
  }
}

// ── Trend Chart ───────────────────────────────────────────────────────────────

class _TrendCard extends StatelessWidget {
  final List<Map> hourly, predictions;
  final Map trend;
  const _TrendCard({required this.hourly, required this.predictions, required this.trend});

  @override
  Widget build(BuildContext context) {
    final trendStr = trend['trend'] as String? ?? 'STABLE';
    final slope = (trend['slope_per_hour'] as num?)?.toDouble() ?? 0.0;
    final trendColor = slope > 1 ? AppColors.red : slope < -1 ? AppColors.green : AppColors.yellow;

    final histSpots = <FlSpot>[];
    for (int i = 0; i < hourly.length; i++) {
      histSpots.add(FlSpot(i.toDouble(),
          (hourly[i]['avg_score'] as num?)?.toDouble() ?? 0.0));
    }
    final predSpots = <FlSpot>[];
    final off = histSpots.length.toDouble();
    for (int i = 0; i < predictions.length && i < 8; i++) {
      predSpots.add(FlSpot(off + i,
          (predictions[i]['score'] as num?)?.toDouble() ?? 0.0));
    }

    return CyberCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionHeader(
          title: 'RISK TREND',
          subtitle: '24H HISTORY + FORECAST',
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: trendColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: trendColor.withValues(alpha: 0.3))),
            child: Text(trendStr.replaceAll('_', ' '),
                style: TextStyle(color: trendColor, fontSize: 9, letterSpacing: 1)),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 160,
          child: histSpots.isEmpty
              ? const Center(child: Text('No data yet',
                  style: TextStyle(color: AppColors.textMuted)))
              : LineChart(LineChartData(
                  minY: 0, maxY: 100,
                  gridData: FlGridData(
                    show: true, drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) =>
                        const FlLine(color: AppColors.border, strokeWidth: 0.5)),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(sideTitles: SideTitles(
                      showTitles: true, reservedSize: 28,
                      getTitlesWidget: (v, _) => Text(v.toInt().toString(),
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 9)),
                    )),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: histSpots, isCurved: true,
                      color: AppColors.cyan, barWidth: 2,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(show: true,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter, end: Alignment.bottomCenter,
                          colors: [AppColors.cyan.withValues(alpha: 0.2),
                            AppColors.cyan.withValues(alpha: 0.0)])),
                    ),
                    if (predSpots.isNotEmpty)
                      LineChartBarData(
                        spots: predSpots, isCurved: true,
                        color: AppColors.yellow.withValues(alpha: 0.6), barWidth: 1.5,
                        dashArray: [4, 4], dotData: const FlDotData(show: false),
                      ),
                  ],
                )),
        ),
        const SizedBox(height: 8),
        Row(children: [
          _dot(AppColors.cyan, 'Historical'),
          const SizedBox(width: 14),
          _dot(AppColors.yellow, 'Predicted', dashed: true),
        ]),
      ]),
    );
  }

  Widget _dot(Color c, String label, {bool dashed = false}) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 14, height: 2, color: c),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
    ]);
  }
}

// ── Distribution Pie ──────────────────────────────────────────────────────────

class _DistributionCard extends StatelessWidget {
  final Map<String, dynamic> labels;
  const _DistributionCard({required this.labels});

  @override
  Widget build(BuildContext context) {
    final normal = (labels['Normal'] as num?)?.toDouble() ?? 0.0;
    final sus = (labels['Suspicious'] as num?)?.toDouble() ?? 0.0;
    final mal = (labels['Malicious'] as num?)?.toDouble() ?? 0.0;
    final total = normal + sus + mal;

    return CyberCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionHeader(title: 'TRAFFIC DISTRIBUTION'),
        const SizedBox(height: 14),
        total == 0
            ? const Center(
                child: Padding(padding: EdgeInsets.all(16),
                  child: Text('No data yet',
                      style: TextStyle(color: AppColors.textMuted))))
            : Row(children: [
                SizedBox(height: 140, width: 140,
                  child: PieChart(PieChartData(
                    sectionsSpace: 3, centerSpaceRadius: 36,
                    sections: [
                      PieChartSectionData(value: normal,
                        color: AppColors.green, radius: 36,
                        title: '${(normal/total*100).toStringAsFixed(0)}%',
                        titleStyle: const TextStyle(color: AppColors.bg0,
                            fontSize: 11, fontWeight: FontWeight.bold)),
                      PieChartSectionData(value: sus,
                        color: AppColors.yellow, radius: 36,
                        title: '${(sus/total*100).toStringAsFixed(0)}%',
                        titleStyle: const TextStyle(color: AppColors.bg0,
                            fontSize: 11, fontWeight: FontWeight.bold)),
                      PieChartSectionData(value: mal,
                        color: AppColors.red, radius: 36,
                        title: '${(mal/total*100).toStringAsFixed(0)}%',
                        titleStyle: const TextStyle(color: AppColors.bg0,
                            fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ))),
                const SizedBox(width: 20),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _PieLegendRow('Normal', normal.toInt(), AppColors.green),
                    const SizedBox(height: 12),
                    _PieLegendRow('Suspicious', sus.toInt(), AppColors.yellow),
                    const SizedBox(height: 12),
                    _PieLegendRow('Malicious', mal.toInt(), AppColors.red),
                  ],
                )),
              ]),
      ]),
    );
  }
}

class _PieLegendRow extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _PieLegendRow(this.label, this.count, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(width: 10, height: 10,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 8),
      Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      const Spacer(),
      Text(count.toString(),
          style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
    ]);
  }
}

// ── Top Sources ───────────────────────────────────────────────────────────────

class _TopSourcesCard extends StatelessWidget {
  final List<Map> sources;
  const _TopSourcesCard({required this.sources});

  @override
  Widget build(BuildContext context) {
    final maxCount = (sources.first['count'] as num?)?.toDouble() ?? 1.0;
    return CyberCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionHeader(title: 'TOP THREAT SOURCES', accentColor: AppColors.red),
        const SizedBox(height: 14),
        ...sources.take(5).map((s) {
          final ip = s['ip'] as String? ?? '—';
          final cnt = (s['count'] as num?)?.toDouble() ?? 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.gps_fixed, color: AppColors.red, size: 12),
                const SizedBox(width: 6),
                Text(ip, style: const TextStyle(color: AppColors.textPrimary,
                    fontSize: 12, fontFamily: 'monospace')),
                const Spacer(),
                Text('${cnt.toInt()} hits',
                    style: const TextStyle(color: AppColors.red, fontSize: 11)),
              ]),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: cnt / maxCount,
                  backgroundColor: AppColors.bg3,
                  valueColor: const AlwaysStoppedAnimation(AppColors.red),
                  minHeight: 3)),
            ]),
          );
        }),
      ]),
    );
  }
}
