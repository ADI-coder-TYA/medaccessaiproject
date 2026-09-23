class PhysiologicalAlert {
  final String type;
  final String severity; // 'CRITICAL_OVERRIDE' | 'MODERATE_WARNING'
  final double value;
  final double threshold;
  final String unit;
  final String clinicalDirective;

  PhysiologicalAlert({
    required this.type,
    required this.severity,
    required this.value,
    required this.threshold,
    required this.unit,
    required this.clinicalDirective,
  });

  factory PhysiologicalAlert.fromJson(Map<String, dynamic> json) {
    return PhysiologicalAlert(
      type: json['type'] as String? ?? 'UNKNOWN',
      severity: json['severity'] as String? ?? 'MODERATE_WARNING',
      value: (json['value'] as num?)?.toDouble() ?? 0.0,
      threshold: (json['threshold'] as num?)?.toDouble() ?? 0.0,
      unit: json['unit'] as String? ?? '',
      clinicalDirective: json['clinicalDirective'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'severity': severity,
      'value': value,
      'threshold': threshold,
      'unit': unit,
      'clinicalDirective': clinicalDirective,
    };
  }
}

class VitalsResult {
  final double heartRateBpm;
  final double hrvRmssdMs;
  final double respirationRateBpm;
  final double oxygenSaturationSpo2;
  final double confidenceScore;
  final double snrDb;
  final int sampleCount;
  final double durationSeconds;
  final List<double> filteredWaveform;
  final List<double> interBeatIntervalsMs;
  final List<PhysiologicalAlert> alerts;
  final bool hasCriticalDerangement;

  VitalsResult({
    required this.heartRateBpm,
    required this.hrvRmssdMs,
    required this.respirationRateBpm,
    required this.oxygenSaturationSpo2,
    required this.confidenceScore,
    required this.snrDb,
    required this.sampleCount,
    required this.durationSeconds,
    required this.filteredWaveform,
    required this.interBeatIntervalsMs,
    required this.alerts,
    required this.hasCriticalDerangement,
  });

  factory VitalsResult.fromJson(Map<String, dynamic> json) {
    final rawWaveform = json['filteredWaveform'];
    final waveformList = (rawWaveform is List)
        ? rawWaveform.map((e) => (e as num).toDouble()).toList()
        : <double>[];

    final rawIbis = json['interBeatIntervalsMs'];
    final ibisList = (rawIbis is List)
        ? rawIbis.map((e) => (e as num).toDouble()).toList()
        : <double>[];

    final rawAlerts = json['alerts'];
    final alertsList = (rawAlerts is List)
        ? rawAlerts
            .map((e) => PhysiologicalAlert.fromJson(e as Map<String, dynamic>))
            .toList()
        : <PhysiologicalAlert>[];

    return VitalsResult(
      heartRateBpm: (json['heartRateBpm'] as num?)?.toDouble() ?? 0.0,
      hrvRmssdMs: (json['hrvRmssdMs'] as num?)?.toDouble() ?? 0.0,
      respirationRateBpm: (json['respirationRateBpm'] as num?)?.toDouble() ?? 0.0,
      oxygenSaturationSpo2: (json['oxygenSaturationSpo2'] as num?)?.toDouble() ?? 0.0,
      confidenceScore: (json['confidenceScore'] as num?)?.toDouble() ?? 0.0,
      snrDb: (json['snrDb'] as num?)?.toDouble() ?? 0.0,
      sampleCount: json['sampleCount'] as int? ?? 0,
      durationSeconds: (json['durationSeconds'] as num?)?.toDouble() ?? 0.0,
      filteredWaveform: waveformList,
      interBeatIntervalsMs: ibisList,
      alerts: alertsList,
      hasCriticalDerangement: json['hasCriticalDerangement'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'heartRateBpm': heartRateBpm,
      'hrvRmssdMs': hrvRmssdMs,
      'respirationRateBpm': respirationRateBpm,
      'oxygenSaturationSpo2': oxygenSaturationSpo2,
      'confidenceScore': confidenceScore,
      'snrDb': snrDb,
      'sampleCount': sampleCount,
      'durationSeconds': durationSeconds,
      'filteredWaveform': filteredWaveform,
      'interBeatIntervalsMs': interBeatIntervalsMs,
      'alerts': alerts.map((a) => a.toJson()).toList(),
      'hasCriticalDerangement': hasCriticalDerangement,
    };
  }
}
