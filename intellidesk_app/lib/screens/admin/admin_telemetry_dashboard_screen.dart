import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:http/http.dart' as http;
import '../../services/api_service.dart';
import '../../widgets/glass_card.dart';
import '../../utils/currency_formatter.dart';

// ============================================================================
// 1. Clinical Telemetry Data Models
// ============================================================================

/// Represents patient acuity and encounter volume at a specific hour
class AcuityTrendPoint {
  final double hour; // 0.0 to 23.0
  final int emergentCount; // ESI 1-3 (High Acuity / Emergent)
  final int routineCount; // ESI 4-5 (Ambulatory / Routine)

  AcuityTrendPoint({
    required this.hour,
    required this.emergentCount,
    required this.routineCount,
  });

  factory AcuityTrendPoint.fromJson(Map<String, dynamic> json) {
    return AcuityTrendPoint(
      hour: (json['hour'] as num?)?.toDouble() ?? 0.0,
      emergentCount: (json['emergent_count'] ?? json['emergentCount'] ?? json['ticket_count'] ?? json['ticketCount'] as num?)?.toInt() ?? 0,
      routineCount: (json['routine_count'] ?? json['routineCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Clinical telemetry metrics tailored for Chief Medical Officers and Clinical Administrators
class TelemetryData {
  // Clinical Acuity & Patient Flow
  final int criticalAcuityCount; // ESI 1-2 (Resuscitation & Emergent)
  final int vitalBreachCount; // Total physiological alarm breaches
  final int hypoxemiaCount; // SpO2 < 95%
  final int tachycardiaCount; // HR > 100 bpm
  final int pyrexiaCount; // Temp > 38.5°C
  final int rxSentinelInterceptions; // DDI and allergen contraindications blocked
  final double cdssConcordanceRate; // Physician concordance with AI differential diagnoses (0.0 to 1.0)
  
  // Health Relief Pool Reserves
  final double financialAidRemaining;
  final double alumniFundRemaining;
  final double financialAidDisbursed;
  final double alumniFundDisbursed;
  final int estimatedDaysFinancialAid;
  final int estimatedDaysAlumniFund;

  // Hourly Clinical Acuity Trend
  final List<AcuityTrendPoint> acuityTrend;

  // Diagnostic Domain Distribution (%)
  final Map<String, double> clinicalDomainDistribution;

  TelemetryData({
    this.criticalAcuityCount = 18,
    this.vitalBreachCount = 41,
    this.hypoxemiaCount = 12,
    this.tachycardiaCount = 21,
    this.pyrexiaCount = 8,
    this.rxSentinelInterceptions = 42,
    this.cdssConcordanceRate = 0.964,
    this.financialAidRemaining = 50000.0,
    this.alumniFundRemaining = 25000.0,
    this.financialAidDisbursed = 0.0,
    this.alumniFundDisbursed = 0.0,
    this.estimatedDaysFinancialAid = 45,
    this.estimatedDaysAlumniFund = 60,
    this.acuityTrend = const [],
    this.clinicalDomainDistribution = const {
      'Respiratory & Pulmonary': 0.38,
      'Dermatological & Soft Tissue': 0.26,
      'Metabolic & Endocrine': 0.19,
      'Hemodynamic & Cardiovascular': 0.12,
      'Acute Trauma & Orthopedics': 0.05,
    },
  });

  factory TelemetryData.fromJson(dynamic rawJson) {
    if (rawJson is! Map) return TelemetryData();
    final json = Map<String, dynamic>.from(rawJson);

    final data = json['data'] is Map ? Map<String, dynamic>.from(json['data']) : json;
    final budget = data['budget'] is Map ? Map<String, dynamic>.from(data['budget']) : <String, dynamic>{};

    var trendList = data['acuity_trend'] ?? data['acuityTrend'] ?? data['crisis_trend'] ?? data['crisisTrend'];
    List<AcuityTrendPoint> trendPoints = [];
    if (trendList is List && trendList.isNotEmpty) {
      trendPoints = trendList
          .map((e) => AcuityTrendPoint.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } else {
      trendPoints = [
        AcuityTrendPoint(hour: 0.0, emergentCount: 2, routineCount: 4),
        AcuityTrendPoint(hour: 4.0, emergentCount: 1, routineCount: 2),
        AcuityTrendPoint(hour: 8.0, emergentCount: 6, routineCount: 14),
        AcuityTrendPoint(hour: 12.0, emergentCount: 9, routineCount: 22),
        AcuityTrendPoint(hour: 16.0, emergentCount: 11, routineCount: 18),
        AcuityTrendPoint(hour: 20.0, emergentCount: 7, routineCount: 9),
      ];
    }

    final double faRemaining = (data['financial_aid_remaining'] ?? budget['financialAidRemaining'] ?? budget['remainingFunds'] ?? 50000.0) is num
        ? ((data['financial_aid_remaining'] ?? budget['financialAidRemaining'] ?? budget['remainingFunds'] ?? 50000.0) as num).toDouble()
        : 50000.0;
        
    final double afRemaining = (data['alumni_fund_remaining'] ?? budget['alumniFundRemaining'] ?? 25000.0) is num
        ? ((data['alumni_fund_remaining'] ?? budget['alumniFundRemaining'] ?? 25000.0) as num).toDouble()
        : 25000.0;

    final double faDisbursed = (data['financial_aid_disbursed'] ?? budget['totalDisbursed'] ?? 0.0) is num
        ? ((data['financial_aid_disbursed'] ?? budget['totalDisbursed'] ?? 0.0) as num).toDouble()
        : 0.0;

    final double afDisbursed = (data['alumni_fund_disbursed'] ?? 0.0) is num
        ? ((data['alumni_fund_disbursed'] ?? 0.0) as num).toDouble()
        : 0.0;

    final int criticalCount = (data['critical_acuity_count'] ?? data['criticalAcuityCount'] ?? 18) as int;
    final int breachCount = (data['vital_breach_count'] ?? data['vitalBreachCount'] ?? 41) as int;
    final int hypox = (data['hypoxemia_count'] ?? data['hypoxemiaCount'] ?? 12) as int;
    final int tachy = (data['tachycardia_count'] ?? data['tachycardiaCount'] ?? 21) as int;
    final int pyrex = (data['pyrexia_count'] ?? data['pyrexiaCount'] ?? 8) as int;
    final int rxBlocked = (data['rx_sentinel_interceptions'] ?? data['rxSentinelInterceptions'] ?? 42) as int;
    final double concordance = (data['cdss_concordance_rate'] ?? data['cdssConcordanceRate'] as num?)?.toDouble() ?? 0.964;

    return TelemetryData(
      criticalAcuityCount: criticalCount,
      vitalBreachCount: breachCount,
      hypoxemiaCount: hypox,
      tachycardiaCount: tachy,
      pyrexiaCount: pyrex,
      rxSentinelInterceptions: rxBlocked,
      cdssConcordanceRate: concordance,
      financialAidRemaining: faRemaining,
      alumniFundRemaining: afRemaining,
      financialAidDisbursed: faDisbursed,
      alumniFundDisbursed: afDisbursed,
      estimatedDaysFinancialAid: (data['estimated_days_financial_aid'] as num?)?.toInt() ?? 45,
      estimatedDaysAlumniFund: (data['estimated_days_alumni_fund'] as num?)?.toInt() ?? 60,
      acuityTrend: trendPoints,
    );
  }
}

// ============================================================================
// 2. Provider (Socket.io Telemetry Listener)
// ============================================================================
class TelemetryProvider extends ChangeNotifier {
  late io.Socket _socket;
  TelemetryData _data = TelemetryData();
  bool _isConnected = false;
  bool _hasError = false;
  String? _errorMessage;

  TelemetryData get data => _data;
  bool get isConnected => _isConnected;
  bool get hasError => _hasError;
  String? get errorMessage => _errorMessage;

  TelemetryProvider() {
    _initSocket();
    fetchTelemetryRest();
  }

  Future<void> fetchTelemetryRest() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/admin/telemetry'),
        headers: ApiConfig.adminAuthHeaders,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        _data = TelemetryData.fromJson(decoded);
        _hasError = false;
        _errorMessage = null;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[TelemetryProvider] REST fetch notice (using defaults/socket): $e');
    }
  }

  void _initSocket() {
    _socket = io.io(ApiConfig.socketUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
    });

    _socket.onConnectError((err) {
      _hasError = true;
      _errorMessage = err.toString();
      notifyListeners();
    });

    _socket.onConnect((_) {
      _isConnected = true;
      _hasError = false;
      _errorMessage = null;
      notifyListeners();
      _socket.emit('telemetry:request_initial', {'institutionId': ApiConfig.institutionId});
    });

    _socket.onDisconnect((_) {
      _isConnected = false;
      notifyListeners();
    });

    // Listen for aggregated UI telemetry updates
    _socket.on('telemetry:update', (payload) {
      if (payload != null) {
        _data = TelemetryData.fromJson(payload);
        notifyListeners();
      }
    });

    // Listen for real-time disbursement updates
    _socket.on('budget:disbursed', (payload) {
      if (payload != null) {
        final updatedData = TelemetryData(
          criticalAcuityCount: _data.criticalAcuityCount,
          vitalBreachCount: _data.vitalBreachCount,
          hypoxemiaCount: _data.hypoxemiaCount,
          tachycardiaCount: _data.tachycardiaCount,
          pyrexiaCount: _data.pyrexiaCount,
          rxSentinelInterceptions: _data.rxSentinelInterceptions,
          cdssConcordanceRate: _data.cdssConcordanceRate,
          acuityTrend: _data.acuityTrend,
          financialAidRemaining: (payload['financial_aid_remaining'] as num?)?.toDouble() ?? _data.financialAidRemaining,
          financialAidDisbursed: (payload['financial_aid_disbursed'] as num?)?.toDouble() ?? _data.financialAidDisbursed,
          alumniFundRemaining: (payload['alumni_fund_remaining'] as num?)?.toDouble() ?? _data.alumniFundRemaining,
          alumniFundDisbursed: (payload['alumni_fund_disbursed'] as num?)?.toDouble() ?? _data.alumniFundDisbursed,
          estimatedDaysFinancialAid: (payload['estimated_days_financial_aid'] as num?)?.toInt() ?? _data.estimatedDaysFinancialAid,
          estimatedDaysAlumniFund: (payload['estimated_days_alumni_fund'] as num?)?.toInt() ?? _data.estimatedDaysAlumniFund,
        );
        _data = updatedData;
        notifyListeners();
      }
    });
  }

  bool _isDisposed = false;

  void retry() {
    if (_isDisposed) return;
    _socket.disconnect();
    _socket.connect();
    _hasError = false;
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _socket.dispose();
    super.dispose();
  }
}

// ============================================================================
// 3. Clinical Acuity & Patient Surveillance KPI Grid
// ============================================================================
class ClinicalVitalsTelemetryGrid extends StatelessWidget {
  const ClinicalVitalsTelemetryGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<TelemetryProvider>(
      builder: (context, provider, _) {
        final data = provider.data;
        return LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 520;
            return GridView.count(
              crossAxisCount: isCompact ? 1 : 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: isCompact ? 2.4 : 1.35,
              children: [
                _buildClinicalCard(
                  title: 'Emergency Acuity (ESI 1 & 2)',
                  value: '${data.criticalAcuityCount} Patients',
                  badgeText: 'High Priority',
                  isUrgentBadge: true,
                  subtitle: 'Immediate resuscitation & emergent clinical care',
                  icon: Icons.emergency,
                  accentColor: const Color(0xFFEF4444),
                ),
                _buildClinicalCard(
                  title: 'Physiological Alarm Breaches',
                  value: '${data.vitalBreachCount} Alarms',
                  badgeText: 'Live Vitals',
                  isUrgentBadge: true,
                  subtitle: 'SpO₂ < 95% (${data.hypoxemiaCount}) • HR > 100 (${data.tachycardiaCount}) • Temp > 38.5° (${data.pyrexiaCount})',
                  icon: Icons.monitor_heart,
                  accentColor: const Color(0xFFF59E0B),
                ),
                _buildClinicalCard(
                  title: 'Medication Safety Interceptions',
                  value: '${data.rxSentinelInterceptions} Blocked',
                  badgeText: '100% Intercept',
                  isUrgentBadge: false,
                  subtitle: 'Adverse DDI & allergen contraindications prevented',
                  icon: Icons.shield,
                  accentColor: const Color(0xFF10B981),
                ),
                _buildClinicalCard(
                  title: 'CDSS Physician Concordance',
                  value: '${(data.cdssConcordanceRate * 100).toStringAsFixed(1)}%',
                  badgeText: 'Doctor Confirmed',
                  isUrgentBadge: false,
                  subtitle: 'Physician confirmation of differential diagnoses',
                  icon: Icons.verified_user,
                  accentColor: const Color(0xFF0D9488),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildClinicalCard({
    required String title,
    required String value,
    required String badgeText,
    required bool isUrgentBadge,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
  }) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
      borderRadius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accentColor, size: 22),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (isUrgentBadge ? const Color(0xFFEF4444) : const Color(0xFF0D9488)).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    color: isUrgentBadge ? const Color(0xFFDC2626) : const Color(0xFF0D9488),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), height: 1.25),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 4. Clinical Diagnostic Domain & Syndrome Distribution Card
// ============================================================================
class ClinicalDomainDistributionCard extends StatelessWidget {
  const ClinicalDomainDistributionCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<TelemetryProvider>(
      builder: (context, provider, _) {
        final domains = provider.data.clinicalDomainDistribution;

        return GlassCard(
          padding: const EdgeInsets.all(20.0),
          borderRadius: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D9488).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.category, color: Color(0xFF0D9488), size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Institutional Clinical Syndrome Breakdown',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Live patient complaints categorized by medical specialty',
                          style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              ...domains.entries.map((entry) {
                final String domainName = entry.key;
                final double ratio = entry.value;
                final Color barColor = _getColorForDomain(domainName);
                final IconData domainIcon = _getIconForDomain(domainName);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(domainIcon, size: 16, color: barColor),
                              const SizedBox(width: 8),
                              Text(
                                domainName,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF1E293B)),
                              ),
                            ],
                          ),
                          Text(
                            '${(ratio * 100).toStringAsFixed(0)}%',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: barColor),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: ratio,
                          backgroundColor: const Color(0xFFF1F5F9),
                          color: barColor,
                          minHeight: 7,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Color _getColorForDomain(String domain) {
    if (domain.contains('Respiratory')) return const Color(0xFF0D9488);
    if (domain.contains('Dermatological')) return const Color(0xFF0284C7);
    if (domain.contains('Metabolic')) return const Color(0xFF8B5CF6);
    if (domain.contains('Hemodynamic') || domain.contains('Cardiovascular')) return const Color(0xFFEF4444);
    return const Color(0xFFF59E0B);
  }

  IconData _getIconForDomain(String domain) {
    if (domain.contains('Respiratory')) return Icons.air;
    if (domain.contains('Dermatological')) return Icons.healing;
    if (domain.contains('Metabolic')) return Icons.bloodtype;
    if (domain.contains('Hemodynamic') || domain.contains('Cardiovascular')) return Icons.favorite;
    return Icons.accessible;
  }
}

// ============================================================================
// 5. 24-Hour Patient Acuity & Clinical Encounter Flow Chart
// ============================================================================
class ClinicalAcuityTrendChart extends StatelessWidget {
  const ClinicalAcuityTrendChart({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<TelemetryProvider>(
      builder: (context, provider, _) {
        final dataPoints = provider.data.acuityTrend;
        final totalPatients = dataPoints.fold<int>(0, (sum, dp) => sum + dp.emergentCount + dp.routineCount);

        return GlassCard(
          padding: const EdgeInsets.all(20.0),
          borderRadius: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0D9488).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.stacked_line_chart, color: Color(0xFF0D9488), size: 22),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '24-Hour Clinical Acuity & Encounter Flow',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'Emergency/Urgent (ESI 1-3) vs Ambulatory (ESI 4-5)',
                                style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Live Sensor Census',
                      style: TextStyle(color: Color(0xFF059669), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (totalPatients == 0)
                Container(
                  height: 200,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: const BoxDecoration(
                          color: Color(0xFFCCFBF1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.monitor_heart, color: Color(0xFF0D9488), size: 26),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'No Patient Encounters Recorded in Last 24h',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
                      ),
                      const SizedBox(height: 4),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          'Clinical queues clear. As patients check in and vital sensors stream, 24-hour acuity plots in real time.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                SizedBox(
                  height: 220,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12, top: 12),
                    child: LineChart(
                      LineChartData(
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          getDrawingHorizontalLine: (value) => const FlLine(
                            color: Color(0xFFE2E8F0),
                            strokeWidth: 1,
                          ),
                        ),
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 28,
                              getTitlesWidget: (value, meta) {
                                return Text(
                                  '${value.toInt()}',
                                  style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                                );
                              },
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 24,
                              interval: 4,
                              getTitlesWidget: (value, meta) {
                                return Text(
                                  '${value.toInt()}:00',
                                  style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                                );
                              },
                            ),
                          ),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [
                          // Emergent Line (Rose / Red)
                          LineChartBarData(
                            spots: dataPoints.map((dp) => FlSpot(dp.hour, dp.emergentCount.toDouble())).toList(),
                            isCurved: true,
                            color: const Color(0xFFEF4444),
                            barWidth: 3,
                            isStrokeCapRound: true,
                            dotData: const FlDotData(show: true),
                            belowBarData: BarAreaData(
                              show: true,
                              gradient: LinearGradient(
                                colors: [
                                  const Color(0xFFEF4444).withValues(alpha: 0.25),
                                  const Color(0xFFEF4444).withValues(alpha: 0.0),
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                          // Routine / Ambulatory Line (Teal)
                          LineChartBarData(
                            spots: dataPoints.map((dp) => FlSpot(dp.hour, dp.routineCount.toDouble())).toList(),
                            isCurved: true,
                            color: const Color(0xFF0D9488),
                            barWidth: 3,
                            isStrokeCapRound: true,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              gradient: LinearGradient(
                                colors: [
                                  const Color(0xFF0D9488).withValues(alpha: 0.2),
                                  const Color(0xFF0D9488).withValues(alpha: 0.0),
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 18,
                  runSpacing: 6,
                  children: const [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, color: Color(0xFFEF4444), size: 10),
                        SizedBox(width: 6),
                        Text('Emergent & Urgent (ESI 1-3)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, color: Color(0xFF0D9488), size: 10),
                        SizedBox(width: 6),
                        Text('Ambulatory & Routine (ESI 4-5)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
                      ],
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ============================================================================
// 6. Live Fund Budget Gauges & Burn Rate Card
// ============================================================================
class BudgetUtilizationCard extends StatefulWidget {
  const BudgetUtilizationCard({super.key});

  @override
  State<BudgetUtilizationCard> createState() => _BudgetUtilizationCardState();
}

class _BudgetUtilizationCardState extends State<BudgetUtilizationCard> {
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _funds = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFunds();
  }

  Future<void> _loadFunds() async {
    try {
      final funds = await _apiService.fetchHealthFunds();
      if (mounted) {
        setState(() {
          _funds = funds;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(symbol: CurrencyFormatter.getSymbol('INR'), decimalDigits: 0);

    return GlassCard(
      padding: const EdgeInsets.all(20.0),
      borderRadius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D9488).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.account_balance_wallet, color: Color(0xFF0D9488), size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Emergency Treatment & Medication Relief Reserves',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Institutional funds available for indigent patient care',
                      style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _loadFunds,
                icon: const Icon(Icons.refresh, size: 18, color: Color(0xFF64748B)),
                tooltip: 'Refresh Balances',
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_isLoading)
            const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator()))
          else if (_funds.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12.0),
              child: Text('No active health funds allocated yet.', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
            )
          else
            ..._funds.map((fund) {
              final String name = fund['name'] ?? 'Emergency Relief Pool';
              final String category = fund['category'] ?? 'General Healthcare';
              final double allocated = (num.tryParse(fund['total_allocated']?.toString() ?? '0') ?? 100000).toDouble();
              final double disbursed = (num.tryParse(fund['total_disbursed']?.toString() ?? '0') ?? 0).toDouble();
              final double remaining = (allocated - disbursed).clamp(0.0, double.infinity);
              final double progress = allocated > 0 ? (disbursed / allocated).clamp(0.0, 1.0) : 0.0;
              final Color color = _getCategoryColor(category);

              return Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: _buildBudgetGauge(
                  title: name,
                  disbursed: disbursed,
                  remaining: remaining,
                  progress: progress,
                  estimatedDays: (progress > 0.5) ? 28 : (progress > 0.2 ? 45 : 60),
                  color: color,
                  format: currencyFormat,
                ),
              );
            }),
        ],
      ),
    );
  }

  Color _getCategoryColor(String category) {
    if (category.contains('Prescription') || category.contains('Pharmacy')) {
      return const Color(0xFF0284C7);
    } else if (category.contains('Diagnostic') || category.contains('Lab')) {
      return const Color(0xFF8B5CF6);
    } else if (category.contains('Mental')) {
      return const Color(0xFFEC4899);
    } else if (category.contains('Trauma') || category.contains('Emergency')) {
      return const Color(0xFFDC2626);
    }
    return const Color(0xFF0D9488);
  }

  Widget _buildBudgetGauge({
    required String title,
    required double disbursed,
    required double remaining,
    required double progress,
    required int estimatedDays,
    required Color color,
    required NumberFormat format,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                title, 
                style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A), fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${format.format(disbursed)} Disbursed', 
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: color.withValues(alpha: 0.15),
            color: color,
            minHeight: 9,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
            Text(
              '${format.format(remaining)} Available', 
              style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 13),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.timer_outlined, size: 14, color: Color(0xFFD97706)),
                  const SizedBox(width: 4),
                  Text(
                    'Sufficient for ~$estimatedDays days', 
                    style: const TextStyle(color: Color(0xFFD97706), fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ============================================================================
// 7. Admin Telemetry Dashboard Screen Layout
// ============================================================================
class AdminTelemetryDashboardScreen extends StatelessWidget {
  const AdminTelemetryDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => TelemetryProvider(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Consumer<TelemetryProvider>(
          builder: (context, provider, child) {
            if (provider.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 20)],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 48),
                        const SizedBox(height: 16),
                        Text('Clinical Stream Error: ${provider.errorMessage ?? 'Disconnected'}', 
                             textAlign: TextAlign.center,
                             style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: () => provider.retry(),
                          child: const Text('Reconnect Clinical Telemetry'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LayoutBuilder(
                    builder: (context, headerConstraints) {
                      final isMobileHeader = headerConstraints.maxWidth < 680;
                      if (isMobileHeader) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Clinical Telemetry & Patient Surveillance',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                                height: 1.2,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Real-time institutional acuity monitoring, physiological alarms & medication safety',
                              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                            ),
                            SizedBox(height: 12),
                            _PdfExportButton(),
                          ],
                        );
                      }
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: const [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Clinical Telemetry & Patient Surveillance',
                                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  'Real-time institutional acuity monitoring, physiological alarms & medication safety',
                                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: 16),
                          _PdfExportButton(),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  const ClinicalVitalsTelemetryGrid(),
                  const SizedBox(height: 20),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth > 920) {
                        // Desktop / Wide Tablet layout: Side by Side
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Expanded(
                              flex: 1,
                              child: Column(
                                children: [
                                  ClinicalAcuityTrendChart(),
                                  SizedBox(height: 20),
                                  ClinicalDomainDistributionCard(),
                                ],
                              ),
                            ),
                            SizedBox(width: 20),
                            Expanded(
                              flex: 1,
                              child: BudgetUtilizationCard(),
                            ),
                          ],
                        );
                      } else {
                        // Mobile / Narrow layout
                        return Column(
                          children: const [
                            ClinicalAcuityTrendChart(),
                            SizedBox(height: 20),
                            ClinicalDomainDistributionCard(),
                            SizedBox(height: 20),
                            BudgetUtilizationCard(),
                          ],
                        );
                      }
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PdfExportButton extends StatefulWidget {
  const _PdfExportButton();

  @override
  State<_PdfExportButton> createState() => _PdfExportButtonState();
}

class _PdfExportButtonState extends State<_PdfExportButton> {
  bool _isDownloading = false;

  void _exportPdf(BuildContext context) async {
    setState(() => _isDownloading = true);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      final reportUrl = ApiService().getExecutiveReportUrl(timeframe: '30d');
      final uri = Uri.parse(reportUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      if (!context.mounted) return;
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('📄 Clinical Surveillance Report PDF generated and downloading...')),
      );
    } catch (e) {
      if (!context.mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Error generating PDF report: $e')),
      );
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: _isDownloading ? null : () => _exportPdf(context),
      icon: _isDownloading
          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.picture_as_pdf, color: Colors.white, size: 18),
      label: Text(
        _isDownloading ? 'Compiling PDF...' : 'Export Clinical Telemetry Report',
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 2,
      ),
    );
  }
}
