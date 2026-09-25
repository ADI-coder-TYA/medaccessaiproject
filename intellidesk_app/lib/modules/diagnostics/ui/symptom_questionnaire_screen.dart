import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_theme.dart';
import '../providers/diagnostic_state_provider.dart';
import '../providers/diagnostics_provider.dart';
import '../services/inference_engine_interface.dart';
import '../services/local_inference_service.dart';
import 'clinical_camera_screen.dart';

class SymptomQuestionnaireScreen extends StatefulWidget {
  const SymptomQuestionnaireScreen({super.key});

  @override
  State<SymptomQuestionnaireScreen> createState() => _SymptomQuestionnaireScreenState();
}

class _SymptomQuestionnaireScreenState extends State<SymptomQuestionnaireScreen> {
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
  }

  Future<void> _checkConnectivity() async {
    final offline = await LocalInferenceService.isOffline();
    if (mounted) {
      setState(() => _isOffline = offline);
    }
  }

  final List<Map<String, dynamic>> _bodyLocations = [
    {'name': 'Head', 'icon': Icons.face, 'desc': 'Eyes, ears, sinus, cranial pain'},
    {'name': 'Throat', 'icon': Icons.mic_none, 'desc': 'Pharynx, tonsils, difficulty swallowing'},
    {'name': 'Skin/Chest', 'icon': Icons.shield_outlined, 'desc': 'Epidermis, thorax, rashes, lesions'},
    {'name': 'Abdomen', 'icon': Icons.fitness_center_outlined, 'desc': 'Stomach, gastrointestinal, cramps'},
    {'name': 'Extremities', 'icon': Icons.pan_tool_outlined, 'desc': 'Arms, hands, legs, joint swelling'},
  ];

  final List<String> _secondarySymptomsList = [
    'Rash',
    'Swelling',
    'Redness',
    'Shortness of Breath',
    'Pruritus (Itching)',
    'Fever / Chills',
    'Open Exudate',
    'Dizziness',
    'Nausea',
    'Fatigue',
  ];

  final List<String> _preExistingConditionsList = [
    'Diabetes',
    'Hypertension',
    'Asthma / COPD',
    'Immunosuppressed',
    'Cardiovascular Disease',
    'Dermatitis History',
    'None',
  ];

  final List<String> _genderOptions = [
    'Female',
    'Male',
    'Non-Binary',
    'Prefer not to say',
  ];

  @override
  void dispose() {
    _ageController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _proceedToCamera() {
    final provider = context.read<DiagnosticStateProvider>();
    if (!provider.isQuestionnaireValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppTheme.emergencyRed,
          content: Text('⚠️ Please select at least one anatomical body location to continue.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_ageController.text.isNotEmpty) {
      provider.setAge(int.tryParse(_ageController.text));
    }
    if (_notesController.text.isNotEmpty) {
      provider.setNotes(_notesController.text.trim());
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ClinicalCameraScreen()),
    );
  }

  Color _getPainColor(int pain) {
    if (pain >= 8) return AppTheme.esi1Critical;
    if (pain >= 5) return AppTheme.esi2Emergent;
    if (pain >= 3) return AppTheme.esi3Urgent;
    return AppTheme.routine;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DiagnosticStateProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : AppTheme.surfaceSlate,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBrand,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Multimodal Health Checkup', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18)),
            Text('Step 1 of 2: Clinical Questionnaire', style: GoogleFonts.outfit(fontSize: 12, color: Colors.white70)),
          ],
        ),
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
          children: [
            // Offline Mode Badge (Requirement: "Processed 100% On-Device (Offline Private Mode)")
            if (_isOffline || context.watch<DiagnosticsProvider>().executionMode == ExecutionMode.localTflite)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF064E3B),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF10B981), width: 1.2),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.offline_bolt_rounded, color: Color(0xFF10B981), size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Processed 100% On-Device (Offline Private Mode)',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF047857),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('OFFLINE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),

            // Header Info Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.primaryContainer.withOpacity(0.5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.primaryBrand.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.analytics_outlined, color: AppTheme.primaryBrand, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Your inputs are fused with clinical computer vision models to estimate risk and highlight salient symptom regions.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppTheme.primaryDark,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 1. Anatomical Body Location Selector
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '1. Primary Symptom Location',
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                if (provider.selectedBodyLocation == null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.emergencyRed.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Required',
                      style: GoogleFonts.inter(fontSize: 11, color: AppTheme.emergencyRed, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            ..._bodyLocations.map((loc) {
              final isSelected = provider.selectedBodyLocation == loc['name'];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: InkWell(
                  onTap: () => provider.setBodyLocation(loc['name'] as String),
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.primaryBrand.withOpacity(0.12)
                          : (isDark ? const Color(0xFF1E293B) : Colors.white),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? AppTheme.primaryBrand : AppTheme.borderSubtle,
                        width: isSelected ? 2.0 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          loc['icon'] as IconData,
                          color: isSelected ? AppTheme.primaryBrand : AppTheme.textMuted,
                          size: 26,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                loc['name'] as String,
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14.5,
                                  color: isSelected ? AppTheme.primaryBrand : (isDark ? Colors.white : AppTheme.textDark),
                                ),
                              ),
                              Text(
                                loc['desc'] as String,
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isSelected)
                          const Icon(Icons.check_circle, color: AppTheme.primaryBrand, size: 22),
                      ],
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 20),

            // 2. Dynamic Clinical Sliders
            Text(
              '2. Dynamic Clinical Metrics',
              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),

            // Slider A: Pain Severity (1 - 10)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.borderSubtle),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Pain Severity (1–10 Scale)', style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: _getPainColor(provider.painSeverity).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${provider.painSeverity} / 10',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: _getPainColor(provider.painSeverity),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: provider.painSeverity.toDouble(),
                    min: 1,
                    max: 10,
                    divisions: 9,
                    activeColor: _getPainColor(provider.painSeverity),
                    onChanged: (val) => provider.setPainSeverity(val.round()),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('1: Mild Discomfort', style: GoogleFonts.inter(fontSize: 10.5, color: AppTheme.textMuted)),
                      Text('10: Debilitating Pain', style: GoogleFonts.inter(fontSize: 10.5, color: AppTheme.textMuted)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Slider B: Symptom Duration (Days)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.borderSubtle),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Symptom Duration', style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600)),
                      Text(
                        '${provider.symptomDurationDays} ${provider.symptomDurationDays == 1 ? "Day" : "Days"}',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryBrand),
                      ),
                    ],
                  ),
                  Slider(
                    value: provider.symptomDurationDays.toDouble().clamp(1, 30),
                    min: 1,
                    max: 30,
                    divisions: 29,
                    activeColor: AppTheme.primaryBrand,
                    onChanged: (val) => provider.setSymptomDuration(val.round()),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Acute (<3 days)', style: GoogleFonts.inter(fontSize: 10.5, color: AppTheme.textMuted)),
                      Text('Sub-acute / Chronic (30+ days)', style: GoogleFonts.inter(fontSize: 10.5, color: AppTheme.textMuted)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Slider C: Fever / Temperature Range
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.borderSubtle),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Fever / Body Temperature', style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600)),
                      Text(
                        '${provider.temperatureCelsius.toStringAsFixed(1)} °C (${((provider.temperatureCelsius * 9 / 5) + 32).toStringAsFixed(1)} °F)',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: provider.temperatureCelsius >= 38.0 ? AppTheme.emergencyRed : AppTheme.primaryBrand,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: provider.temperatureCelsius.clamp(35.0, 41.5),
                    min: 35.0,
                    max: 41.5,
                    divisions: 65,
                    activeColor: provider.temperatureCelsius >= 38.0 ? AppTheme.emergencyRed : AppTheme.accentCyan,
                    onChanged: (val) => provider.setTemperature(val),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('35.0°C (Hypothermic)', style: GoogleFonts.inter(fontSize: 10.5, color: AppTheme.textMuted)),
                      Text('37.0°C (Norm)', style: GoogleFonts.inter(fontSize: 10.5, color: AppTheme.textMuted)),
                      Text('38.5°C+ (High Fever)', style: GoogleFonts.inter(fontSize: 10.5, color: AppTheme.textMuted)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 3. Multi-Select Chips for Secondary Symptoms
            Text(
              '3. Secondary Symptoms',
              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _secondarySymptomsList.map((sym) {
                final isSelected = provider.selectedSecondarySymptoms.contains(sym);
                return FilterChip(
                  label: Text(sym),
                  selected: isSelected,
                  selectedColor: AppTheme.primaryBrand.withOpacity(0.18),
                  checkmarkColor: AppTheme.primaryBrand,
                  labelStyle: GoogleFonts.inter(
                    color: isSelected ? AppTheme.primaryBrand : (isDark ? Colors.white70 : AppTheme.textDark),
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    fontSize: 12.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: isSelected ? AppTheme.primaryBrand : AppTheme.borderSubtle,
                    ),
                  ),
                  onSelected: (_) => provider.toggleSecondarySymptom(sym),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // 4. Demographics Section
            Text(
              '4. Patient Demographics & Pre-Existing Factors',
              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _ageController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Age (Years)',
                            hintText: 'e.g. 24',
                            prefixIcon: const Icon(Icons.cake_outlined, color: AppTheme.primaryBrand),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: provider.gender,
                          decoration: InputDecoration(
                            labelText: 'Gender',
                            prefixIcon: const Icon(Icons.person_outline, color: AppTheme.primaryBrand),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                          ),
                          items: _genderOptions
                              .map((g) => DropdownMenuItem(value: g, child: Text(g, style: const TextStyle(fontSize: 13))))
                              .toList(),
                          onChanged: (val) => provider.setGender(val),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text('Pre-Existing Medical Conditions:', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _preExistingConditionsList.map((cond) {
                      final isSelected = provider.preExistingConditions.contains(cond);
                      return ChoiceChip(
                        label: Text(cond),
                        selected: isSelected,
                        selectedColor: AppTheme.accentCyan.withOpacity(0.18),
                        labelStyle: GoogleFonts.inter(
                          color: isSelected ? AppTheme.accentCyan : (isDark ? Colors.white70 : AppTheme.textDark),
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 11.5,
                        ),
                        onSelected: (_) => provider.togglePreExistingCondition(cond),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Step Progression Button (Disabled if no body location selected)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: provider.isQuestionnaireValid ? AppTheme.primaryBrand : Colors.grey[400],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: provider.isQuestionnaireValid ? 2 : 0,
              ),
              icon: const Icon(Icons.camera_alt),
              label: Text(
                provider.isQuestionnaireValid
                    ? 'Proceed to Clinical Photo Capture'
                    : 'Select Body Location to Continue',
                style: GoogleFonts.outfit(fontSize: 15.5, fontWeight: FontWeight.bold),
              ),
              onPressed: provider.isQuestionnaireValid ? _proceedToCamera : null,
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
