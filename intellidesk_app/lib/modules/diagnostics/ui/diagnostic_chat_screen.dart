import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/diagnostics_provider.dart';

class DiagnosticChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  const DiagnosticChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}

class DiagnosticChatScreen extends StatefulWidget {
  const DiagnosticChatScreen({super.key});

  @override
  State<DiagnosticChatScreen> createState() => _DiagnosticChatScreenState();
}

class _DiagnosticChatScreenState extends State<DiagnosticChatScreen> {
  final List<DiagnosticChatMessage> _messages = [];
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isResponding = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final diag = context.read<DiagnosticsProvider>();
      final assessment = diag.currentAssessment;

      final initialGreeting = assessment != null
          ? 'Hello! I have reviewed your checkup results for **${assessment.primaryDiagnosis}** (Risk: ${assessment.riskLevel.displayName}). I am here to help answer any questions or guide you through immediate comforting and psychological first aid measures. How can I help you today?'
          : 'Hello! I am your MedAccess AI Health Assistant. How can I support your health and well-being today?';

      setState(() {
        _messages.add(DiagnosticChatMessage(
          text: initialGreeting,
          isUser: false,
          timestamp: DateTime.now(),
        ));
      });
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final query = _textController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _messages.add(DiagnosticChatMessage(
        text: query,
        isUser: true,
        timestamp: DateTime.now(),
      ));
      _isResponding = true;
    });
    _textController.clear();
    _scrollToBottom();

    // Context-aware PFA / clinical response simulation
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      final diag = context.read<DiagnosticsProvider>();
      final assessment = diag.currentAssessment;

      final responseText = _generateHealthAssistantResponse(query, assessment?.primaryDiagnosis);

      setState(() {
        _messages.add(DiagnosticChatMessage(
          text: responseText,
          isUser: false,
          timestamp: DateTime.now(),
        ));
        _isResponding = false;
      });
      _scrollToBottom();
    });
  }

  String _generateHealthAssistantResponse(String query, String? condition) {
    final lower = query.toLowerCase();
    if (lower.contains('pain') || lower.contains('hurt') || lower.contains('itch')) {
      return 'I hear that you are experiencing discomfort. Try applying a clean, cool compress for 10-15 minutes if appropriate, and avoid scratching the area. If pain escalates sharply, please visit an urgent care center.';
    }
    if (lower.contains('emergency') || lower.contains('hospital') || lower.contains('doctor')) {
      return 'If you notice severe chest tightness, high fever (>39°C), breathing difficulty, or rapidly spreading redness, do not wait—seek urgent emergency medical evaluation immediately.';
    }
    if (lower.contains('anxious') || lower.contains('scared') || lower.contains('worried')) {
      return 'It is completely normal to feel stressed when facing physical symptoms. Let us take a slow, deep breath together: inhale for 4 seconds, hold for 4, and exhale for 6. Your body is resilient, and we are taking the right steps by monitoring these findings.';
    }
    return 'Thank you for sharing that. Based on the evaluation for ${condition ?? 'your current symptoms'}, following the recommended hydration and monitoring plan is key. Feel free to re-screen if you notice any new visual changes.';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            CircleAvatar(
              backgroundColor: Color(0xFF0D9488),
              radius: 16,
              child: Icon(Icons.favorite, color: Colors.white, size: 18),
            ),
            SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Qwen2.5 PFA Assistant', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text('Psychological First Aid & Guidance', style: TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16.0),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  return Align(
                    alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 6.0),
                      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                      decoration: BoxDecoration(
                        color: msg.isUser
                            ? const Color(0xFF0D9488)
                            : (Theme.of(context).brightness == Brightness.dark
                                ? Colors.grey[800]
                                : Colors.grey[200]),
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(16),
                          topRight: const Radius.circular(16),
                          bottomLeft: msg.isUser ? const Radius.circular(16) : const Radius.circular(4),
                          bottomRight: msg.isUser ? const Radius.circular(4) : const Radius.circular(16),
                        ),
                      ),
                      child: Text(
                        msg.text,
                        style: TextStyle(
                          color: msg.isUser ? Colors.white : (Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87),
                          fontSize: 14,
                          height: 1.35,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_isResponding)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
                child: Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2.0, color: Color(0xFF0D9488)),
                    ),
                    SizedBox(width: 8),
                    Text('Qwen2.5 is thinking...', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, -2)),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      decoration: InputDecoration(
                        hintText: 'Ask a question about your screening...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF0D9488),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.send, size: 20),
                    onPressed: _sendMessage,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
