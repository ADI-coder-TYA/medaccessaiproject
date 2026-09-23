import '../models/symptom_vector.dart';
import '../models/risk_assessment.dart';

/// Defines where diagnostic inference executes.
enum ExecutionMode {
  /// Cloud server execution via MedAccess AI Backend REST API.
  backendApi,

  /// On-device edge execution using local Neural Engine / GPU via TFLite / ONNX.
  localTflite;

  String get label {
    switch (this) {
      case ExecutionMode.backendApi:
        return 'Cloud API (High Precision)';
      case ExecutionMode.localTflite:
        return 'On-Device Edge (Offline / Low Latency)';
    }
  }
}

/// Abstract contract for Clinical Vision & Multimodal Diagnostic Inference engines.
abstract class InferenceEngineInterface {
  /// Active execution target.
  ExecutionMode get executionMode;

  /// Loads weights, delegates, or initializes HTTP/socket transports.
  Future<void> initialize();

  /// Checks if the model runtime/weights or server endpoints are available.
  Future<bool> isModelAvailable();

  /// Extracts dense latent visual embedding vector (128-d or 512-d) from an image file/bytes.
  Future<List<double>> extractVisualEmbeddings(dynamic imageInput);

  /// Fuses structured symptoms, vitals, visual embeddings, and audio biomarkers into a unified clinical risk assessment.
  Future<RiskAssessment> runMultimodalInference(
    SymptomVector symptoms, {
    List<double>? visionEmbeddings,
    String? imageUrl,
    dynamic audioBytes,
    List<double>? audioFeatures,
  });

  /// Releases resources, native memory, or open handles.
  void dispose();
}
