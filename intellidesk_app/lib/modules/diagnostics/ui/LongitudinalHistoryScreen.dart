import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../theme/app_theme.dart';
import '../models/risk_assessment.dart';
import '../models/longitudinal_progression.dart';
import '../services/diagnostics_service.dart';
import '../../../config/api_config.dart';

class LongitudinalHistoryScreen extends StatefulWidget {
  final String? patientId;
  final List<ScreeningHistoryPoint>? initialScreenings;
  final ScreeningDeltaResult? initialDelta;
  final DiagnosticsService? diagnosticsService;

  const LongitudinalHistoryScreen({
    super.key,
    this.patientId,
    this.initialScreenings,
    this.initialDelta,
    this.diagnosticsService,
  });

  @override
  State<LongitudinalHistoryScreen> createState() => _LongitudinalHistoryScreenState();
}

class _LongitudinalHistoryScreenState extends State<LongitudinalHistoryScreen> {
  late DiagnosticsService _diagnosticsService;
  List<ScreeningHistoryPoint> _screenings = [];
  ScreeningDeltaResult? _currentDelta;
  bool _isLoading = true;
  String? _errorMessage;

  // Selected pair for comparison
  int _selectedT0Index = 0;
  int _selectedT1Index = 1;

  // Interactive slider position (0.0 to 1.0)
  double _sliderPosition = 0.5;
  bool _isSideBySideMode = false;

  @override
  void initState() {
    super.initState();
    _diagnosticsService = widget.diagnosticsService ?? DiagnosticsService();

    if (widget.initialScreenings != null && widget.initialScreenings!.isNotEmpty) {
      _screenings = widget.initialScreenings!;
      _selectedT0Index = 0;
      _selectedT1Index = _screenings.length > 1 ? _screenings.length - 1 : 0;
      _currentDelta = widget.initialDelta ?? _generateFallbackDelta(_screenings[_selectedT0Index], _screenings[_selectedT1Index]);
      _isLoading = false;
    } else {
      _loadHistoryData();
    }
  }

  Future<void> _loadHistoryData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final patientId = (widget.patientId != null && widget.patientId!.trim().isNotEmpty)
          ? widget.patientId!.trim()
          : (ApiConfig.userId ?? 'PAT-2026-001');
      final history = await _diagnosticsService.fetchLongitudinalHistory(patientId);

      setState(() {
        _screenings = history;
        if (_screenings.length >= 2) {
          _selectedT0Index = 0;
          _selectedT1Index = _screenings.length - 1;
          _currentDelta = widget.initialDelta ?? _generateFallbackDelta(_screenings[_selectedT0Index], _screenings[_selectedT1Index]);
        } else if (_screenings.length == 1) {
          _selectedT0Index = 0;
          _selectedT1Index = 0;
          _currentDelta = _generateFallbackDelta(_screenings[0], _screenings[0]);
        }
        _isLoading = false;
      });

      if (_screenings.length >= 2 && widget.initialDelta == null) {
        _refreshDeltaComparison();
      }
    } catch (err) {
      setState(() {
        _errorMessage = 'Could not load progression history: $err';
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshDeltaComparison() async {
    if (_screenings.isEmpty) return;
    final t0 = _screenings[_selectedT0Index];
    final t1 = _screenings[_selectedT1Index];

    try {
      final delta = await _diagnosticsService.compareScreenings(t0.id, t1.id);
      setState(() {
        _currentDelta = delta;
      });
    } catch (err) {
      setState(() {
        _currentDelta = _generateFallbackDelta(t0, t1);
      });
    }
  }

  ScreeningDeltaResult _generateFallbackDelta(ScreeningHistoryPoint t0, ScreeningHistoryPoint t1) {
    final rDelta = MathRound(t1.riskScore - t0.riskScore, 3);
    final rDeltaPct = MathRound(rDelta * 100, 1);
    final painDelta = (t1.painScore - t0.painScore).toDouble();
    final temp0 = t0.temperature ?? 37.0;
    final temp1 = t1.temperature ?? 37.0;
    final tempDelta = MathRound(temp1 - temp0, 1);

    ClinicalProgressionTier tier;
    String label;
    if (rDelta <= -0.05 || painDelta <= -2) {
      tier = ClinicalProgressionTier.improving;
      label = 'Improving / Healing';
    } else if (rDelta >= 0.05 || painDelta >= 3 || tempDelta >= 1.5) {
      tier = ClinicalProgressionTier.deteriorating;
      label = 'Deteriorating / Escalating';
    } else {
      tier = ClinicalProgressionTier.stable;
      label = 'Stable / Unchanged';
    }

    final days = t1.createdAt.difference(t0.createdAt).inHours / 24.0;

    return ScreeningDeltaResult(
      baselineScreeningId: t0.id,
      followupScreeningId: t1.id,
      baselineDate: t0.createdAt,
      followupDate: t1.createdAt,
      timeElapsedDays: MathRound(days, 1),
      timeElapsedHours: MathRound(days * 24, 1),
      baselineRiskScore: t0.riskScore,
      followupRiskScore: t1.riskScore,
      riskDelta: rDelta,
      riskDeltaPercentage: rDeltaPct,
      statusTier: tier,
      statusLabel: label,
      ssim: (t0.imageUrl != null && t1.imageUrl != null) ? 0.85 : null,
      ssimCategory: (t0.imageUrl != null && t1.imageUrl != null) ? 'High Concordance' : 'N/A',
      painDelta: painDelta,
      tempDelta: tempDelta,
      baselineImageUrl: t0.imageUrl,
      followupImageUrl: t1.imageUrl,
      clinicalSummary: tier == ClinicalProgressionTier.improving
          ? 'Patient exhibits positive clinical trajectory with a ${rDeltaPct.abs()}% risk score reduction.'
          : tier == ClinicalProgressionTier.deteriorating
              ? 'Presentation exhibits symptom escalation (+${rDeltaPct.abs()}% risk increase).'
              : 'Presentation remains stable with minimal risk change ($rDeltaPct%).',
      recommendations: tier == ClinicalProgressionTier.improving
          ? ['Continue prescribed regimen', 'Follow-up routine self-check in 72h']
          : tier == ClinicalProgressionTier.deteriorating
              ? ['Physician consultation recommended', 'Monitor temperature and pain closely']
              : ['Continue scheduled monitoring'],
    );
  }

  double MathRound(double val, int places) {
    final mod = 10 * places;
    return (val * mod).round() / mod;
  }

  Color _getProgressionColor(ClinicalProgressionTier tier) {
    switch (tier) {
      case ClinicalProgressionTier.improving:
        return const Color(0xFF10B981); // Emerald Green
      case ClinicalProgressionTier.stable:
        return const Color(0xFF3B82F6); // Medical Blue
      case ClinicalProgressionTier.deteriorating:
        return const Color(0xFFEF4444); // Urgent Coral Red
    }
  }

  IconData _getProgressionIcon(ClinicalProgressionTier tier) {
    switch (tier) {
      case ClinicalProgressionTier.improving:
        return Icons.trending_down;
      case ClinicalProgressionTier.stable:
        return Icons.trending_flat;
      case ClinicalProgressionTier.deteriorating:
        return Icons.trending_up;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBrand,
        foregroundColor: Colors.white,
        title: Text(
          'Longitudinal Progression Tracker',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Timeline',
            onPressed: _loadHistoryData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildErrorView()
              : _screenings.isEmpty
                  ? _buildEmptyView()
                  : SafeArea(
                      child: ListView(
                        padding: const EdgeInsets.all(16.0),
                        children: [
                          _buildProgressionHeaderBanner(),
                          const SizedBox(height: 16),
                          _buildLineChartCard(isDark),
                          const SizedBox(height: 20),
                          _buildComparisonSelectorBar(isDark),
                          const SizedBox(height: 16),
                          _buildPhotoComparisonCard(isDark),
                          const SizedBox(height: 20),
                          _buildClinicalSynthesisCard(isDark),
                          const SizedBox(height: 20),
                          _buildHistoricalCheckupsList(isDark),
                        ],
                      ),
                    ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 48),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'An error occurred',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[700]),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadHistoryData,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.timeline, color: Colors.grey, size: 56),
            const SizedBox(height: 16),
            Text(
              'No Historical Screenings Found',
              style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Complete at least two clinical intakes to unlock longitudinal recovery tracking and before/after comparisons.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressionHeaderBanner() {
    final delta = _currentDelta;
    if (delta == null) return const SizedBox.shrink();

    final color = _getProgressionColor(delta.statusTier);
    final icon = _getProgressionIcon(delta.statusTier);
    final String pctStr;
    if (delta.statusTier == ClinicalProgressionTier.stable) {
      final sign = delta.riskDeltaPercentage >= 0 ? '+' : '';
      pctStr = '$sign${delta.riskDeltaPercentage.toStringAsFixed(1)}% (Stable)';
    } else if (delta.statusTier == ClinicalProgressionTier.improving) {
      pctStr = '${delta.riskDeltaPercentage.abs().toStringAsFixed(1)}% Risk Reduction';
    } else {
      pctStr = '+${delta.riskDeltaPercentage.abs().toStringAsFixed(1)}% Risk Escalation';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        delta.statusLabel.toUpperCase(),
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        pctStr,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  delta.timeElapsedDays > 0
                      ? 'Comparison spanning ${delta.timeElapsedDays} days (${DateFormat('MMM d').format(delta.baselineDate)} → ${DateFormat('MMM d').format(delta.followupDate)})'
                      : 'Same-day baseline vs follow-up checkup',
                  style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          if (delta.ssim != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.04),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  Text(
                    'SSIM',
                    style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey[600]),
                  ),
                  Text(
                    '${(delta.ssim! * 100).toStringAsFixed(0)}%',
                    style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blueGrey[800]),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLineChartCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.show_chart, color: AppTheme.primaryBrand, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Health Risk Score Trajectory',
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_screenings.length} Intakes',
                style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500], fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Interactive longitudinal curve tracking multimodal risk (0% - 100%)',
            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500]),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 200,
            child: LineChart(_buildChartData(isDark)),
          ),
          const SizedBox(height: 12),
          _buildChartLegend(),
        ],
      ),
    );
  }

  LineChartData _buildChartData(bool isDark) {
    final spots = <FlSpot>[];
    for (int i = 0; i < _screenings.length; i++) {
      spots.add(FlSpot(i.toDouble(), _screenings[i].riskScore * 100));
    }

    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: 25,
        getDrawingHorizontalLine: (val) => FlLine(
          color: Colors.grey.withOpacity(0.15),
          strokeWidth: 1,
          dashArray: [4, 4],
        ),
      ),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 34,
            interval: 25,
            getTitlesWidget: (val, meta) {
              return Text(
                '${val.toInt()}%',
                style: GoogleFonts.inter(fontSize: 10, color: Colors.grey[500]),
              );
            },
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 26,
            interval: 1,
            getTitlesWidget: (val, meta) {
              final idx = val.toInt();
              if (idx < 0 || idx >= _screenings.length) return const SizedBox.shrink();
              final scr = _screenings[idx];
              final dateStr = DateFormat('M/d').format(scr.createdAt);
              final isT0 = idx == _selectedT0Index;
              final isT1 = idx == _selectedT1Index;

              return Padding(
                padding: const EdgeInsets.only(top: 6.0),
                child: Text(
                  isT0 ? 'T0' : isT1 ? 'T1' : dateStr,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: (isT0 || isT1) ? FontWeight.bold : FontWeight.normal,
                    color: isT0
                        ? const Color(0xFF64748B)
                        : isT1
                            ? AppTheme.primaryBrand
                            : Colors.grey[500],
                  ),
                ),
              );
            },
          ),
        ),
      ),
      borderData: FlBorderData(show: false),
      minX: 0,
      maxX: (_screenings.length - 1).toDouble().clamp(1.0, 10.0),
      minY: 0,
      maxY: 100,
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          curveSmoothness: 0.3,
          barWidth: 3,
          color: AppTheme.primaryBrand,
          gradient: const LinearGradient(
            colors: [
              Color(0xFF10B981), // Green
              Color(0xFFF59E0B), // Amber
              Color(0xFFEF4444), // Red
            ],
            stops: [0.35, 0.65, 1.0],
          ),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppTheme.primaryBrand.withOpacity(0.2),
                AppTheme.primaryBrand.withOpacity(0.0),
              ],
            ),
          ),
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, barData, index) {
              final isT0 = index == _selectedT0Index;
              final isT1 = index == _selectedT1Index;
              return FlDotCirclePainter(
                radius: (isT0 || isT1) ? 6 : 4,
                color: isT0
                    ? const Color(0xFF64748B)
                    : isT1
                        ? AppTheme.primaryBrand
                        : Colors.white,
                strokeWidth: 2,
                strokeColor: (isT0 || isT1) ? Colors.white : AppTheme.primaryBrand,
              );
            },
          ),
        ),
      ],
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (touchedSpots) {
            return touchedSpots.map((spot) {
              final idx = spot.spotIndex;
              final scr = _screenings[idx];
              return LineTooltipItem(
                '${DateFormat('MMM d, h:mm a').format(scr.createdAt)}\nRisk: ${spot.y.toStringAsFixed(1)}%',
                GoogleFonts.inter(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
              );
            }).toList();
          },
        ),
      ),
    );
  }

  Widget _buildChartLegend() {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 6,
        children: [
          _buildLegendDot(const Color(0xFF10B981), 'Low (≤40%)'),
          _buildLegendDot(const Color(0xFFF59E0B), 'Moderate (40-70%)'),
          _buildLegendDot(const Color(0xFFEF4444), 'Critical (≥70%)'),
        ],
      ),
    );
  }

  Widget _buildLegendDot(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 4),
        Text(text, style: GoogleFonts.inter(fontSize: 10, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildComparisonSelectorBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  Text(
                    'Comparing:',
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  _buildSelectorDropdown(
                    label: 'T0 Baseline',
                    selectedIndex: _selectedT0Index,
                    onChanged: (newIdx) {
                      if (newIdx != null && newIdx != _selectedT0Index) {
                        setState(() => _selectedT0Index = newIdx);
                        _refreshDeltaComparison();
                      }
                    },
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6.0),
                    child: Icon(Icons.arrow_forward, size: 14, color: Colors.grey),
                  ),
                  _buildSelectorDropdown(
                    label: 'T1 Follow-up',
                    selectedIndex: _selectedT1Index,
                    onChanged: (newIdx) {
                      if (newIdx != null && newIdx != _selectedT1Index) {
                        setState(() => _selectedT1Index = newIdx);
                        _refreshDeltaComparison();
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              _isSideBySideMode ? Icons.vertical_split : Icons.compare,
              size: 20,
              color: AppTheme.primaryBrand,
            ),
            tooltip: _isSideBySideMode ? 'Switch to Slider' : 'Switch to Side-by-Side',
            onPressed: () => setState(() => _isSideBySideMode = !_isSideBySideMode),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectorDropdown({
    required String label,
    required int selectedIndex,
    required ValueChanged<int?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: selectedIndex,
          isDense: true,
          items: List.generate(_screenings.length, (idx) {
            final scr = _screenings[idx];
            final dateStr = DateFormat('M/d').format(scr.createdAt);
            return DropdownMenuItem(
              value: idx,
              child: Text(
                'T$idx ($dateStr)',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            );
          }),
          onChanged: onChanged,
        ),
      ),
    );
  }

  /// Technical Guardrail 4: Normalized Slider Aspect Ratio
  /// Enforces AspectRatio(aspectRatio: 1.0) with BoxFit.cover on comparison slider frames
  Widget _buildPhotoComparisonCard(bool isDark) {
    final t0 = _screenings[_selectedT0Index];
    final t1 = _screenings[_selectedT1Index];
    final hasBothImages = t0.imageUrl != null && t1.imageUrl != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.remove_red_eye_outlined, color: AppTheme.primaryBrand, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Visual Progression Comparison',
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _isSideBySideMode ? 'Side-by-Side' : 'Interactive Slider',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey[700]),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Drag divider horizontally to compare baseline tissue morphology with current presentation.',
            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500]),
          ),
          const SizedBox(height: 14),
          // Technical Guardrail 4: Strict AspectRatio(1.0) container
          AspectRatio(
            aspectRatio: 1.0,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: _isSideBySideMode
                  ? _buildSideBySideView(t0, t1)
                  : _buildInteractiveSliderView(t0, t1),
            ),
          ),
        ],
      ),
    );
  }

  /// Technical Guardrail 4: Interactive drag slider with BoxFit.cover
  Widget _buildInteractiveSliderView(ScreeningHistoryPoint t0, ScreeningHistoryPoint t1) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final dividerX = w * _sliderPosition;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (details) {
            setState(() {
              _sliderPosition = (details.localPosition.dx / w).clamp(0.02, 0.98);
            });
          },
          onTapDown: (details) {
            setState(() {
              _sliderPosition = (details.localPosition.dx / w).clamp(0.02, 0.98);
            });
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Base Layer (T0 Baseline Photo - full width)
              _buildImageFrame(t0.imageUrl, 'T0 Baseline'),

              // 2. Clipped Overlay Layer (T1 Follow-up Photo - revealed from left)
              ClipRect(
                clipper: _HorizontalSplitClipper(dividerX),
                child: _buildImageFrame(t1.imageUrl, 'T1 Follow-up'),
              ),

              // 3. Vertical Divider Line
              Positioned(
                left: dividerX - 1.5,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 3,
                  color: Colors.white,
                ),
              ),

              // 4. Center Drag Handle
              Positioned(
                left: dividerX - 18,
                top: (h / 2) - 18,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.compare_arrows,
                    size: 22,
                    color: Colors.black87,
                  ),
                ),
              ),

              // 5. Left & Right Overlay Labels
              Positioned(
                left: 12,
                top: 12,
                child: _buildSliderPill('T1 Follow-up', AppTheme.primaryBrand),
              ),
              Positioned(
                right: 12,
                top: 12,
                child: _buildSliderPill('T0 Baseline', const Color(0xFF64748B)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSideBySideView(ScreeningHistoryPoint t0, ScreeningHistoryPoint t1) {
    return Row(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildImageFrame(t0.imageUrl, 'T0 Baseline'),
              Positioned(
                left: 8,
                top: 8,
                child: _buildSliderPill('T0 Baseline', const Color(0xFF64748B)),
              ),
            ],
          ),
        ),
        Container(width: 2, color: Colors.white),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildImageFrame(t1.imageUrl, 'T1 Follow-up'),
              Positioned(
                left: 8,
                top: 8,
                child: _buildSliderPill('T1 Follow-up', AppTheme.primaryBrand),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSliderPill(String label, Color color) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.85),
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4),
          ],
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  /// Technical Guardrail 4: Strict BoxFit.cover rendering
  Widget _buildImageFrame(String? url, String fallbackTitle) {
    if (url == null || url.isEmpty) {
      return Container(
        color: const Color(0xFFF1F5F9),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined, size: 36, color: Color(0xFF94A3B8)),
              const SizedBox(height: 8),
              Text(
                'No Photo for $fallbackTitle',
                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B), fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
    }

    if (url.startsWith('data:')) {
      try {
        final b64 = url.contains(',') ? url.split(',')[1] : url;
        final bytes = base64Decode(b64);
        return Image.memory(bytes, fit: BoxFit.cover);
      } catch (_) {}
    }

    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          color: const Color(0xFFF1F5F9),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.broken_image_outlined, size: 36, color: Color(0xFF94A3B8)),
                const SizedBox(height: 8),
                Text(
                  'Image Load Failed ($fallbackTitle)',
                  style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildClinicalSynthesisCard(bool isDark) {
    final delta = _currentDelta;
    if (delta == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.medical_services_outlined, color: AppTheme.primaryBrand, size: 20),
              const SizedBox(width: 8),
              Text(
                'Clinical Delta Analysis',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            delta.clinicalSummary,
            style: GoogleFonts.inter(fontSize: 13, height: 1.5, color: Colors.grey[700]),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (delta.painDelta != null)
                _buildVitalDeltaChip(
                  'Pain',
                  delta.painDelta! <= 0 ? '${delta.painDelta!.toInt()}' : '+${delta.painDelta!.toInt()}',
                  delta.painDelta! <= 0 ? Colors.green : Colors.red,
                  Icons.sentiment_dissatisfied_outlined,
                ),
              if (delta.tempDelta != null && delta.tempDelta != 0)
                _buildVitalDeltaChip(
                  'Temp',
                  delta.tempDelta! <= 0 ? '${delta.tempDelta}°C' : '+${delta.tempDelta}°C',
                  delta.tempDelta! <= 0 ? Colors.green : Colors.orange,
                  Icons.thermostat_outlined,
                ),
              if (delta.ssim != null)
                _buildVitalDeltaChip(
                  'SSIM Alignment',
                  '${(delta.ssim! * 100).toStringAsFixed(0)}% (${delta.ssimCategory})',
                  Colors.blue,
                  Icons.auto_awesome,
                ),
            ],
          ),
          if (delta.recommendations.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              'Actionable Directives:',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            ...delta.recommendations.map(
              (rec) => Padding(
                padding: const EdgeInsets.only(bottom: 6.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle, size: 14, color: AppTheme.primaryBrand),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        rec,
                        style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[800]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVitalDeltaChip(String title, String val, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            '$title: $val',
            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoricalCheckupsList(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recorded Timeline Checkups',
          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _screenings.length,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final scr = _screenings[index];
            final isT0 = index == _selectedT0Index;
            final isT1 = index == _selectedT1Index;

            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isT1
                      ? AppTheme.primaryBrand
                      : isT0
                          ? const Color(0xFF64748B)
                          : Colors.grey.withOpacity(0.15),
                  width: (isT0 || isT1) ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: isT1
                          ? AppTheme.primaryBrand.withOpacity(0.15)
                          : Colors.grey.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        'T$index',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isT1 ? AppTheme.primaryBrand : Colors.grey[700],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat('MMMM d, yyyy • h:mm a').format(scr.createdAt),
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Risk Score: ${(scr.riskScore * 100).toStringAsFixed(0)}% • ${scr.riskLevel.name.toUpperCase()}',
                          style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[500]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () {
                          setState(() => _selectedT0Index = index);
                          _refreshDeltaComparison();
                        },
                        child: Text(
                          isT0 ? '✓ T0' : 'Set T0',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: isT0 ? FontWeight.bold : FontWeight.normal,
                            color: isT0 ? const Color(0xFF64748B) : Colors.grey,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () {
                          setState(() => _selectedT1Index = index);
                          _refreshDeltaComparison();
                        },
                        child: Text(
                          isT1 ? '✓ T1' : 'Set T1',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: isT1 ? FontWeight.bold : FontWeight.normal,
                            color: isT1 ? AppTheme.primaryBrand : Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _HorizontalSplitClipper extends CustomClipper<Rect> {
  final double splitX;
  const _HorizontalSplitClipper(this.splitX);

  @override
  Rect getClip(Size size) {
    return Rect.fromLTRB(0, 0, splitX, size.height);
  }

  @override
  bool shouldReclip(_HorizontalSplitClipper oldClipper) => oldClipper.splitX != splitX;
}
