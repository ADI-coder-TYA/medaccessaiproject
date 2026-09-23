import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/diagnostics_provider.dart';
import '../models/symptom_vector.dart';
import '../services/inference_engine_interface.dart';
import '../services/audio_recorder_service.dart';
import '../../pharmacy/models/medication_entity.dart';
import '../../pharmacy/services/rx_sentinel_service.dart';
import '../../pharmacy/ui/prescription_review_modal.dart';
import '../../pharmacy/ui/patient_allergy_profile_screen.dart';
import '../vitals/models/vitals_result.dart';
import '../vitals/ui/vitals_scanner_modal.dart';
import 'diagnostic_camera_screen.dart';

class DiagnosticIntakeScreen extends StatefulWidget {
  final AudioRecorderService? audioRecorderService;

  const DiagnosticIntakeScreen({super.key, this.audioRecorderService});

  @override
  State<DiagnosticIntakeScreen> createState() => _DiagnosticIntakeScreenState();
}

class _DiagnosticIntakeScreenState extends State<DiagnosticIntakeScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _notesController = TextEditingController();
  final RxSentinelService _sentinelService = RxSentinelService();
  RxScanSummary? _rxScanSummary;
  bool _isScanningRx = false;
  final TextEditingController _tempController = TextEditingController();
  final TextEditingController _hrController = TextEditingController();
  final TextEditingController _bpController = TextEditingController();
  final TextEditingController _spo2Controller = TextEditingController();
  final TextEditingController _rrController = TextEditingController();
  VitalsResult? _scannedVitals;

  late AudioRecorderService _audioRecorder;
  bool _ownsAudioRecorder = false;

  String _selectedBodyLocation = 'Skin / Epidermis';
  int _durationDays = 3;
  double _painScale = 4.0;
  final Set<String> _selectedSymptoms = {'Erythema / Redness', 'Pruritus / Itching'};

  final List<String> _bodyLocations = [
    'Skin / Epidermis',
    'Face / Head',
    'Throat / Oral Cavity',
    'Eyes / Periorbital',
    'Chest / Thorax',
    'Abdomen',
    'Arms / Hands',
    'Legs / Feet',
  ];

  final List<String> _commonSymptoms = [
    'Erythema / Redness',
    'Pruritus / Itching',
    'Swelling / Edema',
    'Localized Warmth',
    'Fever / Chills',
    'Throat Irritation',
    'Conjunctival Discharge',
    'Open Exudate / Crusting',
    'Fatigue / Malaise',
    'Acute Sharp Pain',
    'Wheezing / Stridor Sound',
    'Persistent Cough',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.audioRecorderService != null) {
      _audioRecorder = widget.audioRecorderService!;
      _ownsAudioRecorder = false;
    } else {
      _audioRecorder = AudioRecorderService();
      _ownsAudioRecorder = true;
    }
    _audioRecorder.addListener(_onAudioRecorderStateChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DiagnosticsProvider>().startNewSession();
    });
  }

  void _onAudioRecorderStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    _tempController.dispose();
    _hrController.dispose();
    _bpController.dispose();
    _spo2Controller.dispose();
    _rrController.dispose();
    _audioRecorder.removeListener(_onAudioRecorderStateChanged);
    if (_ownsAudioRecorder) {
      _audioRecorder.dispose();
    }
    super.dispose();
  }

  void _proceedToCamera() {
    final vitals = ClinicalVitals(
      temperatureCelsius: double.tryParse(_tempController.text),
      heartRate: double.tryParse(_hrController.text),
      systolicBP: double.tryParse(_bpController.text),
      oxygenSaturation: double.tryParse(_spo2Controller.text),
      respiratoryRate: double.tryParse(_rrController.text),
      source: _scannedVitals != null ? 'rppg_camera' : 'manual_input',
      rppgResult: _scannedVitals?.toJson(),
    );

    final vector = SymptomVector(
      bodyLocation: _selectedBodyLocation,
      durationDays: _durationDays,
      painScale: _painScale.round(),
      symptoms: _selectedSymptoms.toList(),
      vitals: vitals,
      additionalNotes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
    );

    context.read<DiagnosticsProvider>().updateSymptomVector(vector);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DiagnosticCameraScreen(
          symptomCategoryHint: _mapLocationToCategoryHint(_selectedBodyLocation),
        ),
      ),
    );
  }

  String _mapLocationToCategoryHint(String loc) {
    if (loc.contains('Throat')) return 'ORAL_THROAT_INFECTION';
    if (loc.contains('Eyes')) return 'CONJUNCTIVITIS_EYE';
    if (loc.contains('Skin') || loc.contains('Arms') || loc.contains('Legs')) return 'DERMATOLOGY_RASH';
    return 'GENERAL_PHYSICAL_SYMPTOM';
  }

  void _openVitalsScanner() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      builder: (_) => VitalsScannerModal(
        onVitalsCaptured: (vitals) {
          setState(() {
            _scannedVitals = vitals;
            _hrController.text = vitals.heartRateBpm.round().toString();
            _spo2Controller.text = vitals.oxygenSaturationSpo2.toStringAsFixed(1);
            _rrController.text = vitals.respirationRateBpm.round().toString();
          });
        },
      ),
    );
  }

  Widget _buildVitalChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.06),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final diag = context.watch<DiagnosticsProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clinical Health Intake', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          PopupMenuButton<ExecutionMode>(
            initialValue: diag.executionMode,
            tooltip: 'Inference Engine',
            icon: Icon(
              diag.executionMode == ExecutionMode.localTflite ? Icons.memory : Icons.cloud_done,
              color: const Color(0xFF0D9488),
            ),
            onSelected: (mode) => diag.setExecutionMode(mode),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: ExecutionMode.backendApi,
                child: Row(
                  children: [
                    Icon(Icons.cloud_outlined, color: Color(0xFF0D9488)),
                    SizedBox(width: 8),
                    Text('Cloud AI (Accurate)'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: ExecutionMode.localTflite,
                child: Row(
                  children: [
                    Icon(Icons.memory, color: Color(0xFF0D9488)),
                    SizedBox(width: 8),
                    Text('On-Device Edge (Offline)'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              // Mode banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D9488).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF0D9488).withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(
                      diag.executionMode == ExecutionMode.localTflite ? Icons.bolt : Icons.health_and_safety,
                      color: const Color(0xFF0D9488),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Engine: ${diag.executionMode.label}',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF0D9488)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // 1. Body Location Selector
              const Text('1. Anatomical Symptom Location', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedBodyLocation,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.accessibility_new, color: Color(0xFF0D9488)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                ),
                items: _bodyLocations
                    .map((loc) => DropdownMenuItem(value: loc, child: Text(loc)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedBodyLocation = val);
                },
              ),
              const SizedBox(height: 20),

              // 2. Symptoms Checklist
              const Text('2. Specific Symptoms Observed', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _commonSymptoms.map((sym) {
                  final isSelected = _selectedSymptoms.contains(sym);
                  return FilterChip(
                    label: Text(sym),
                    selected: isSelected,
                    selectedColor: const Color(0xFF0D9488).withOpacity(0.2),
                    checkmarkColor: const Color(0xFF0D9488),
                    labelStyle: TextStyle(
                      color: isSelected ? const Color(0xFF0D9488) : (isDark ? Colors.white : Colors.black87),
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedSymptoms.add(sym);
                        } else {
                          _selectedSymptoms.remove(sym);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // 3. Pain Scale Slider (1 - 10)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('3. Pain Scale (0 - 10)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _painScale >= 7
                          ? Colors.red.withOpacity(0.15)
                          : (_painScale >= 4 ? Colors.amber.withOpacity(0.2) : Colors.green.withOpacity(0.15)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_painScale.round()} / 10',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _painScale >= 7 ? Colors.red : (_painScale >= 4 ? Colors.amber[900] : Colors.green[800]),
                      ),
                    ),
                  ),
                ],
              ),
              Slider(
                value: _painScale,
                min: 0,
                max: 10,
                divisions: 10,
                activeColor: const Color(0xFF0D9488),
                onChanged: (val) => setState(() => _painScale = val),
              ),
              const SizedBox(height: 16),

              // 4. Duration & Vitals
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('4. Clinical Baseline & Vitals', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  TextButton.icon(
                    onPressed: _openVitalsScanner,
                    icon: const Icon(Icons.favorite, color: Color(0xFF0D9488), size: 18),
                    label: const Text('Scan with Camera', style: TextStyle(color: Color(0xFF0D9488), fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Prominent Camera rPPG Trigger Button
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                child: ElevatedButton.icon(
                  key: const Key('scanVitalsWithCameraButton'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0D9488).withOpacity(0.12),
                    foregroundColor: const Color(0xFF0D9488),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: Color(0xFF0D9488), width: 1.2),
                    ),
                  ),
                  icon: const Icon(Icons.camera_front_outlined),
                  label: const Text(
                    'Scan Vitals with Camera (15s rPPG)',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  onPressed: _openVitalsScanner,
                ),
              ),

              // Active rPPG Vitals Badge (if scanned)
              if (_scannedVitals != null) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _scannedVitals!.hasCriticalDerangement
                        ? Colors.red.withOpacity(0.15)
                        : const Color(0xFF0D9488).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _scannedVitals!.hasCriticalDerangement
                          ? Colors.redAccent
                          : const Color(0xFF0D9488).withOpacity(0.5),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _scannedVitals!.hasCriticalDerangement ? Icons.warning : Icons.check_circle,
                            color: _scannedVitals!.hasCriticalDerangement ? Colors.redAccent : const Color(0xFF0D9488),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _scannedVitals!.hasCriticalDerangement
                                  ? 'Optical Vitals Alert (Red-Flag Triggered)'
                                  : 'Optical rPPG Vitals Active (${(_scannedVitals!.confidenceScore * 100).round()}% Conf)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _scannedVitals!.hasCriticalDerangement ? Colors.redAccent : const Color(0xFF0D9488),
                                fontSize: 13,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 16, color: Colors.grey),
                            tooltip: 'Clear rPPG vitals',
                            onPressed: () {
                              setState(() {
                                _scannedVitals = null;
                                _hrController.clear();
                                _spo2Controller.clear();
                                _rrController.clear();
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _buildVitalChip('HR: ${_scannedVitals!.heartRateBpm.round()} BPM'),
                          _buildVitalChip('SpO2: ${_scannedVitals!.oxygenSaturationSpo2.toStringAsFixed(1)}%'),
                          _buildVitalChip('RR: ${_scannedVitals!.respirationRateBpm.round()}/min'),
                          _buildVitalChip('HRV: ${_scannedVitals!.hrvRmssdMs.round()} ms'),
                        ],
                      ),
                      if (_scannedVitals!.hasCriticalDerangement) ...[
                        const SizedBox(height: 8),
                        ..._scannedVitals!.alerts.map(
                          (a) => Text(
                            '⚠️ ${a.clinicalDirective}',
                            style: const TextStyle(color: Colors.redAccent, fontSize: 11.5, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],

              // Vitals Inputs Grid (Temp, HR, SpO2, RR, BP, Duration)
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _tempController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Temp (°C)',
                        hintText: 'e.g. 37.8',
                        prefixIcon: const Icon(Icons.thermostat, color: Color(0xFF0D9488)),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _hrController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Heart Rate (bpm)',
                        hintText: 'e.g. 84',
                        prefixIcon: const Icon(Icons.favorite, color: Colors.redAccent),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _spo2Controller,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Oxygen SpO2 (%)',
                        hintText: 'e.g. 98.0',
                        prefixIcon: const Icon(Icons.air, color: Colors.lightBlueAccent),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _rrController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Respiration (/min)',
                        hintText: 'e.g. 16',
                        prefixIcon: const Icon(Icons.waves, color: Colors.tealAccent),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _bpController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Systolic BP (mmHg)',
                        hintText: 'e.g. 120',
                        prefixIcon: const Icon(Icons.speed, color: Color(0xFF0D9488)),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _durationDays,
                      decoration: InputDecoration(
                        labelText: 'Duration',
                        prefixIcon: const Icon(Icons.calendar_today, color: Color(0xFF0D9488)),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: [1, 2, 3, 5, 7, 14, 30]
                          .map((d) => DropdownMenuItem(value: d, child: Text('$d days')))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _durationDays = val);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 5. Respiratory Acoustic Intake
              _buildAudioRecordingSection(context, isDark),
              const SizedBox(height: 20),

              // 6. Notes
              const Text('6. Patient Notes / Context (Optional)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _notesController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Clinical Notes',
                  hintText: 'Describe onset or any known allergies...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 20),

              // 6. RxSentinel Medication & Allergy Shield
              _buildRxSentinelSection(context, isDark),
              const SizedBox(height: 28),

              // Next: Camera Capture Button
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D9488),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 2,
                ),
                icon: const Icon(Icons.camera_alt),
                label: const Text(
                  'Capture Symptom Photo',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                onPressed: _proceedToCamera,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAudioRecordingSection(BuildContext context, bool isDark) {
    final diag = context.watch<DiagnosticsProvider>();
    final status = _audioRecorder.status;
    final hasRecordedAudio = diag.hasAudio || _audioRecorder.lastResult != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: status == AudioRecorderStatus.recording
              ? Colors.redAccent
              : const Color(0xFF0D9488).withOpacity(0.3),
          width: status == AudioRecorderStatus.recording ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D9488).withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mic, color: Color(0xFF0D9488), size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '5. Respiratory Acoustic Intake',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '5s Cough / Breathing Sound (16 kHz Mono WAV)',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // If currently recording:
          if (status == AudioRecorderStatus.recording) ...[
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Recording Cough... ${_audioRecorder.remainingSeconds}s remaining',
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Animated waveform visualizer bars
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(12, (index) {
                      final heights = [14.0, 26.0, 18.0, 36.0, 22.0, 42.0, 30.0, 48.0, 24.0, 38.0, 18.0, 12.0];
                      final h = heights[index % heights.length];
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2.5),
                        width: 4,
                        height: h,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D9488),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () => _audioRecorder.cancel(),
                    icon: const Icon(Icons.close, size: 16, color: Colors.grey),
                    label: const Text('Cancel Recording', style: TextStyle(color: Colors.grey)),
                  ),
                ],
              ),
            ),
          ]
          // If permission denied:
          else if (status == AudioRecorderStatus.permissionDenied) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.shade700.withOpacity(0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.mic_off, color: Colors.amber.shade800, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _audioRecorder.errorMessage ?? 'Microphone permission denied.',
                          style: TextStyle(fontSize: 13, color: Colors.amber.shade900, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    key: const Key('grantMicPermissionButton'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber.shade700,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    ),
                    icon: const Icon(Icons.settings, size: 16),
                    label: const Text('Grant Mic Permission'),
                    onPressed: () async {
                      final granted = await _audioRecorder.requestMicPermission();
                      if (granted) {
                        _startRecording(diag);
                      }
                    },
                  ),
                ],
              ),
            ),
          ]
          // If recorded:
          else if (hasRecordedAudio) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0D9488).withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF0D9488).withOpacity(0.4)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle, color: Color(0xFF0D9488), size: 24),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Acoustic Sample Captured',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0D9488)),
                            ),
                            Text(
                              '16,000 Hz Mono PCM WAV (5.0s)',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove audio',
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                        onPressed: () {
                          diag.clearCapturedAudio();
                          _audioRecorder.reset();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const Key('retakeCoughSoundButton'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0D9488),
                      side: const BorderSide(color: Color(0xFF0D9488)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.replay, size: 18),
                    label: const Text('Retake Cough / Sound'),
                    onPressed: () => _startRecording(diag),
                  ),
                ],
              ),
            ),
          ]
          // Default idle state:
          else ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                key: const Key('recordCoughSoundButton'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D9488).withOpacity(0.12),
                  foregroundColor: const Color(0xFF0D9488),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Color(0xFF0D9488), width: 1.2),
                  ),
                ),
                icon: const Icon(Icons.mic),
                label: const Text(
                  'Record Cough / Breathing Sound (5s)',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                onPressed: () => _startRecording(diag),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _startRecording(DiagnosticsProvider diag) {
    _audioRecorder.start5SecondRecording(onComplete: () {
      final res = _audioRecorder.lastResult;
      if (res != null) {
        diag.setCapturedAudio(res.wavBytes, fileName: res.fileName);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('5s Respiratory acoustic sample captured (16 kHz mono WAV)'),
              duration: Duration(seconds: 2),
              backgroundColor: Color(0xFF0D9488),
            ),
          );
        }
      }
    });
  }

  Widget _buildRxSentinelSection(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF0D9488).withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D9488).withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.shield_outlined, color: Color(0xFF0D9488), size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '6. RxSentinel Medication Safety',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Scan doctor prescription or check drug allergies',
                      style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.medication_outlined, size: 18),
                  label: const Text('My Allergies & Meds', style: TextStyle(fontSize: 12.5)),
                  onPressed: () {
                    final diag = context.read<DiagnosticsProvider>();
                    final patientId = diag.currentSession?.patientId ?? 'guest-patient';
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PatientAllergyProfileScreen(patientId: patientId),
                      ),
                    );
                  },
                ),
              ),
              if (_rxScanSummary != null) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _rxScanSummary!.hasSafetyConflict
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: Icon(
                      _rxScanSummary!.hasSafetyConflict ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                      size: 18,
                    ),
                    label: Text(
                      _rxScanSummary!.hasSafetyConflict ? 'Alerts (DDI)' : 'Verified Safe',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () => PrescriptionReviewModal.show(context, summary: _rxScanSummary!),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
