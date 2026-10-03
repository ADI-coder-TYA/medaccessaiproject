import 'dart:async';
import 'package:flutter/material.dart';
import '../models/vitals_result.dart';
import '../services/rppg_sensor_service.dart';

class VitalsScannerModal extends StatefulWidget {
  final ValueChanged<VitalsResult>? onVitalsCaptured;
  final bool autoStart;
  final bool enableSimulationMode;

  const VitalsScannerModal({
    super.key,
    this.onVitalsCaptured,
    this.autoStart = true,
    this.enableSimulationMode = false,
  });

  static Future<VitalsResult?> show(
    BuildContext context, {
    bool enableSimulationMode = false,
  }) {
    return showModalBottomSheet<VitalsResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.88,
          child: VitalsScannerModal(
            enableSimulationMode: enableSimulationMode,
            autoStart: true,
          ),
        ),
      ),
    );
  }

  @override
  State<VitalsScannerModal> createState() => _VitalsScannerModalState();
}

class _VitalsScannerModalState extends State<VitalsScannerModal>
    with SingleTickerProviderStateMixin {
  final RPPGSensorService _sensorService = RPPGSensorService();
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  bool _isInitializing = true;
  bool _isScanning = false;
  bool _isProcessing = false;
  bool _isSimulationMode = false;
  String? _errorMessage;

  int _remainingSeconds = 15;
  Timer? _countdownTimer;
  Timer? _waveformTimer;
  StreamSubscription<OpticalFrameData>? _frameSubscription;

  bool _isFingerDetected = false;
  bool _isMotionDetected = false;
  final List<double> _waveformPoints = [];

  VitalsResult? _vitalsResult;

  @override
  void initState() {
    super.initState();
    _isSimulationMode = widget.enableSimulationMode;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _initCameraAndStart();
  }

  Future<void> _initCameraAndStart() async {
    if (_isSimulationMode) {
      setState(() {
        _isInitializing = false;
      });
      if (widget.autoStart) {
        _startSimulationScan();
      }
      return;
    }

    setState(() {
      _isInitializing = true;
      _errorMessage = null;
    });

    final success = await _sensorService.initializeCamera();
    if (!mounted) return;

    if (!success) {
      setState(() {
        _isInitializing = false;
        _isSimulationMode = true;
        _errorMessage = _sensorService.torchStatusMessage ?? 'Camera unavailable on device';
      });
      if (widget.autoStart) {
        _startSimulationScan();
      }
      return;
    }

    setState(() {
      _isInitializing = false;
    });

    if (widget.autoStart) {
      _startLiveScan();
    }
  }

  void _startLiveScan() async {
    setState(() {
      _isScanning = true;
      _isProcessing = false;
      _remainingSeconds = 15;
      _vitalsResult = null;
      _waveformPoints.clear();
    });

    _frameSubscription = _sensorService.frameStream.listen((frame) {
      if (!mounted) return;
      setState(() {
        _isFingerDetected = frame.isFingerDetected;
        _isMotionDetected = frame.isMotionArtifactDetected;
        // In fingertip contact mode, plot pulsing red channel; otherwise plot green for face rPPG
        final pointValue = frame.isFingerDetected ? frame.red : frame.green;
        _waveformPoints.add(pointValue);
        if (_waveformPoints.length > 50) {
          _waveformPoints.removeAt(0);
        }
      });
    });

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
        } else {
          timer.cancel();
          _finishScanAndAnalyze();
        }
      });
    });

    try {
      await _sensorService.startAcquisition(
        targetDurationSeconds: 15,
        onCompleted: () {
          if (_isScanning) {
            _finishScanAndAnalyze();
          }
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isScanning = false;
        _errorMessage = 'Acquisition error: $e';
      });
    }
  }

  void _startSimulationScan() {
    setState(() {
      _isScanning = true;
      _isProcessing = false;
      _remainingSeconds = 5; // Fast 5s simulation
      _vitalsResult = null;
      _waveformPoints.clear();
      _isFingerDetected = true;
      _isMotionDetected = false;
    });

    _waveformTimer?.cancel();
    _waveformTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final step = _waveformPoints.length;
      final val = 128.0 + 15.0 * (step % 10 == 0 ? 1.0 : -0.2);
      setState(() {
        _waveformPoints.add(val);
        if (_waveformPoints.length > 50) {
          _waveformPoints.removeAt(0);
        }
      });
    });

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
        } else {
          timer.cancel();
          _waveformTimer?.cancel();
          _finishSimulationAnalyze();
        }
      });
    });
  }

  Future<void> _finishSimulationAnalyze() async {
    setState(() {
      _isScanning = false;
      _isProcessing = true;
    });

    // Generate authentic simulated physiological data
    final syntheticFrames = RPPGSensorService.generateSyntheticFrames(
      durationSeconds: 15.0,
      heartRateBpm: 74.0,
      respirationRateBpm: 16.0,
      spo2Percent: 98.0,
    );

    try {
      final result = await _sensorService.processVitalsOnBackend(frames: syntheticFrames);
      if (!mounted) return;
      setState(() {
        _vitalsResult = result;
        _isProcessing = false;
      });
    } catch (e) {
      // Local mock fallback if backend unreachable
      if (!mounted) return;
      setState(() {
        _vitalsResult = VitalsResult(
          heartRateBpm: 74.0,
          hrvRmssdMs: 42.5,
          respirationRateBpm: 16.0,
          oxygenSaturationSpo2: 98.0,
          confidenceScore: 0.94,
          snrDb: 18.2,
          sampleCount: 450,
          durationSeconds: 15.0,
          filteredWaveform: [],
          interBeatIntervalsMs: [800.0, 810.0, 795.0, 805.0],
          alerts: [],
          hasCriticalDerangement: false,
        );
        _isProcessing = false;
      });
    }
  }

  Future<void> _finishScanAndAnalyze() async {
    _countdownTimer?.cancel();
    _frameSubscription?.cancel();
    await _sensorService.stopAcquisition();

    if (!mounted) return;
    setState(() {
      _isScanning = false;
      _isProcessing = true;
    });

    try {
      final result = await _sensorService.processVitalsOnBackend();
      if (!mounted) return;
      setState(() {
        _vitalsResult = result;
        _isProcessing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _vitalsResult = RPPGSensorService.computeLocalVitalsEstimate(_sensorService.collectedFrames);
      });
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _waveformTimer?.cancel();
    _frameSubscription?.cancel();
    _pulseController.dispose();
    _sensorService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A), // Slate 900 dark theme
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D9488).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.favorite, color: Color(0xFF14B8A6), size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Touchless Vitals Scanner',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      _isSimulationMode ? 'Simulation / Demo Mode' : '15-Second Optical rPPG',
                      style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Guardrail 4: Ambient Lighting Guidance Banner (Torch Fallback)
          if (_sensorService.torchStatusMessage != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.light_mode, color: Colors.amber, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _sensorService.torchStatusMessage!,
                      style: const TextStyle(fontSize: 12, color: Colors.amberAccent),
                    ),
                  ),
                ],
              ),
            ),

          // Active Scanning UI or Results UI
          if (_isInitializing)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: CircularProgressIndicator(color: Color(0xFF14B8A6)),
            )
          else if (_isScanning || _isProcessing)
            _buildActiveScanningView()
          else if (_vitalsResult != null)
            _buildResultsView()
          else
            _buildIdleView(),
        ],
      ),
    );
  }

  Widget _buildActiveScanningView() {
    return Column(
      children: [
        const SizedBox(height: 16),

        // Live Contact & Motion Status Chips
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _isFingerDetected
                    ? Colors.green.withOpacity(0.2)
                    : Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _isFingerDetected ? Colors.green : Colors.orange,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isFingerDetected ? Icons.check_circle : Icons.touch_app,
                    color: _isFingerDetected ? Colors.greenAccent : Colors.orangeAccent,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _isFingerDetected ? 'Fingertip Detected' : 'Cover Lens Firmly',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _isFingerDetected ? Colors.greenAccent : Colors.orangeAccent,
                    ),
                  ),
                ],
              ),
            ),
            if (_isMotionDetected) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.redAccent, width: 1),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning, color: Colors.redAccent, size: 14),
                    SizedBox(width: 4),
                    Text(
                      'Hold Still',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.redAccent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 20),

        // Pulsing Heart with Countdown Timer
        ScaleTransition(
          scale: _pulseAnimation,
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.redAccent.withOpacity(0.15),
              boxShadow: [
                BoxShadow(
                  color: Colors.redAccent.withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Center(
              child: _isProcessing
                  ? const CircularProgressIndicator(color: Colors.redAccent)
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.favorite, color: Colors.redAccent, size: 36),
                        const SizedBox(height: 4),
                        Text(
                          '${_remainingSeconds}s',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Live Optical Waveform Sparkline
        Container(
          height: 50,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: CustomPaint(
            painter: WaveformPainter(
              points: _waveformPoints,
              color: _isFingerDetected ? Colors.redAccent : const Color(0xFF14B8A6),
            ),
          ),
        ),
        const SizedBox(height: 12),

        Text(
          _isProcessing
              ? 'Analyzing bio-signals via Radix-2 FFT & Butterworth filter...'
              : 'Keep index fingertip steadily covering the rear camera lens',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.grey[300]),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildResultsView() {
    final v = _vitalsResult!;
    return Column(
      children: [
        const SizedBox(height: 8),

        // Critical Red-Flag Banner (if any)
        if (v.hasCriticalDerangement)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.redAccent),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.warning, color: Colors.redAccent, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'PHYSIOLOGICAL RED-FLAG DETECTED',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ...v.alerts.map(
                  (a) => Text(
                    '• ${a.clinicalDirective}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),

        // 4 Vitals Grid Cards
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                title: 'Heart Rate',
                value: '${v.heartRateBpm.round()}',
                unit: 'BPM',
                icon: Icons.favorite,
                iconColor: Colors.redAccent,
                statusColor: v.heartRateBpm >= 130 || v.heartRateBpm <= 40
                    ? Colors.redAccent
                    : Colors.greenAccent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                title: 'Blood Oxygen',
                value: '${v.oxygenSaturationSpo2.toStringAsFixed(1)}',
                unit: '% SpO2',
                icon: Icons.air,
                iconColor: Colors.lightBlueAccent,
                statusColor: v.oxygenSaturationSpo2 <= 90.0
                    ? Colors.redAccent
                    : (v.oxygenSaturationSpo2 < 95.0 ? Colors.amberAccent : Colors.greenAccent),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                title: 'Respiration',
                value: '${v.respirationRateBpm.round()}',
                unit: 'breaths/min',
                icon: Icons.waves,
                iconColor: Colors.tealAccent,
                statusColor: v.respirationRateBpm >= 28 ? Colors.redAccent : Colors.greenAccent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                title: 'HRV (RMSSD)',
                value: '${v.hrvRmssdMs.round()}',
                unit: 'ms',
                icon: Icons.timeline,
                iconColor: Colors.purpleAccent,
                statusColor: Colors.purpleAccent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Signal Quality Chip
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.insights, size: 14, color: Colors.grey[400]),
            const SizedBox(width: 6),
            Text(
              'Signal Quality: ${(v.confidenceScore * 100).round()}% (SNR: ${v.snrDb} dB)',
              style: TextStyle(fontSize: 12, color: Colors.grey[400]),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Action Buttons
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  if (_isSimulationMode) {
                    _startSimulationScan();
                  } else {
                    _startLiveScan();
                  }
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white24),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Retest'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: () {
                  if (widget.onVitalsCaptured != null) {
                    widget.onVitalsCaptured!(v);
                  }
                  Navigator.of(context).pop(v);
                },
                icon: const Icon(Icons.check, color: Colors.white),
                label: const Text(
                  'Apply Vitals',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D9488),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildIdleView() {
    return Column(
      children: [
        if (_errorMessage != null)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
            ),
          ),
        ElevatedButton.icon(
          onPressed: _startLiveScan,
          icon: const Icon(Icons.videocam, color: Colors.white),
          label: const Text('Start 15s Vitals Scan', style: TextStyle(color: Colors.white)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0D9488),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _startSimulationScan,
          child: const Text('Run Demo Simulation', style: TextStyle(color: Colors.grey)),
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String unit,
    required IconData icon,
    required Color iconColor,
    required Color statusColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B), // Slate 800
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: TextStyle(color: Colors.grey[500], fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class WaveformPainter extends CustomPainter {
  final List<double> points;
  final Color color;

  WaveformPainter({
    required this.points,
    this.color = const Color(0xFF14B8A6),
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final minVal = points.reduce((a, b) => a < b ? a : b);
    final maxVal = points.reduce((a, b) => a > b ? a : b);
    final range = (maxVal - minVal).abs() == 0 ? 1.0 : (maxVal - minVal).abs();

    final path = Path();
    final dx = size.width / (points.length - 1);

    for (int i = 0; i < points.length; i++) {
      final normalizedY = (points[i] - minVal) / range;
      final y = size.height - (normalizedY * (size.height - 8) + 4);
      final x = i * dx;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) => true;
}
