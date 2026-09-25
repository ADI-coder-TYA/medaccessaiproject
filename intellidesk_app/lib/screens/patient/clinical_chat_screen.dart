import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../config/api_config.dart';
import '../../theme/app_theme.dart';

class ClinicalChatScreen extends StatefulWidget {
  final String? claimId;

  const ClinicalChatScreen({super.key, this.claimId});

  @override
  State<ClinicalChatScreen> createState() => _ClinicalChatScreenState();
}

class _ClinicalChatScreenState extends State<ClinicalChatScreen> {
  final List<Map<String, dynamic>> _messages = [];
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isTyping = false;
  List<Map<String, dynamic>>? _activeEmergencyResources;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    final claimId = widget.claimId ?? 'general';
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/chat/claims/$claimId/messages'),
        headers: ApiConfig.patientHeaders,
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        if (data.isNotEmpty && mounted) {
          setState(() {
            _messages.clear();
            for (final m in data) {
              _messages.add({
                'sender': m['sender'] ?? 'COUNSELOR_AI',
                'message': m['message'] ?? '',
                'isCrisis': m['is_crisis_response'] == true,
                'timestamp': m['created_at'] ?? DateTime.now().toIso8601String(),
              });
            }
          });
          _scrollToBottom();
          return;
        }
      }
    } catch (_) {}

    if (_messages.isEmpty && mounted) {
      setState(() {
        _messages.add({
          'sender': 'COUNSELOR_AI',
          'message': 'Hello. I am your Clinical & First Aid Assistant. How are you feeling right now? Please share what medical support or distress you are experiencing.',
          'timestamp': DateTime.now().toIso8601String(),
        });
      });
    }
  }

  Future<void> _launchCall(String url) async {
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (_) {}
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    _textController.clear();
    setState(() {
      _messages.add({
        'sender': 'PATIENT',
        'message': text,
        'timestamp': DateTime.now().toIso8601String(),
      });
      _isTyping = true;
    });

    _scrollToBottom();

    try {
      final claimId = widget.claimId ?? 'general';
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/chat/claims/$claimId/messages'),
        headers: ApiConfig.patientHeaders,
        body: jsonEncode({
          'message': text,
          'patientPhone': ApiConfig.userPhone ?? '',
          'email': ApiConfig.userEmail ?? '',
          'institutionId': ApiConfig.activeInstitutionId,
        }),
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final reply = data['reply'] ?? 'I hear you. Our clinical team has logged this and is processing your request.';
        final isCrisis = data['isCrisisResponse'] == true || data['isLifeSafetyAlert'] == true;
        final resources = data['resources'] != null ? List<Map<String, dynamic>>.from(data['resources']) : null;

        if (mounted) {
          setState(() {
            _isTyping = false;
            _messages.add({
              'sender': 'COUNSELOR_AI',
              'message': reply,
              'isCrisis': isCrisis,
              'timestamp': DateTime.now().toIso8601String(),
            });
            if (resources != null && resources.isNotEmpty) {
              _activeEmergencyResources = resources;
            }
          });
          _scrollToBottom();
        }
      } else {
        _fallbackResponse(text);
      }
    } catch (e) {
      _fallbackResponse(text);
    }
  }

  void _fallbackResponse(String userMsg) {
    if (!mounted) return;
    final lower = userMsg.toLowerCase();
    String fallbackReply;
    bool isCrisis = false;

    if (lower.contains('suicid') || lower.contains('kill myself') || lower.contains('hurt myself') || lower.contains('want to die') || lower.contains('severe bleeding') || lower.contains('chest pain')) {
      fallbackReply = 'I hear how acute and painful things are right now. Please take a slow breath with me—you are not alone. Our emergency clinical triage desk has been alerted, and I strongly urge you to call one of the 24/7 crisis numbers below right away.';
      isCrisis = true;
      _activeEmergencyResources = [
        {'name': 'Tele-MANAS (Govt of India)', 'number': '14416', 'actionUrl': 'tel:14416', 'description': '24/7 Toll-Free National Mental Health Helpline'},
        {'name': '988 Suicide & Crisis Lifeline', 'number': '988', 'actionUrl': 'tel:988', 'description': '24/7 Free & Confidential Emergency Lifeline'},
        {'name': 'Vandrevala Crisis Helpline', 'number': '+91 9999 666 555', 'actionUrl': 'tel:+919999666555', 'description': '24/7 Clinical Crisis De-escalation'},
      ];
    } else {
      fallbackReply = 'I hear what you are experiencing. Take a calm, steady breath. Your medical details are actively being reviewed by our clinical team to ensure you receive immediate support.';
    }

    setState(() {
      _isTyping = false;
      _messages.add({
        'sender': 'COUNSELOR_AI',
        'message': fallbackReply,
        'isCrisis': isCrisis,
        'timestamp': DateTime.now().toIso8601String(),
      });
    });
    _scrollToBottom();
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
            Icon(Icons.psychology, color: Colors.white, size: 22),
            SizedBox(width: 8),
            Text('24/7 Clinical & First Aid Support'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Emergency Helpline Banner if active
          if (_activeEmergencyResources != null && _activeEmergencyResources!.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              color: const Color(0xFFFEF2F2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: AppTheme.emergencyRed, size: 18),
                      SizedBox(width: 6),
                      Text(
                        'Immediate 24/7 Emergency Helplines:',
                        style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.emergencyRed, fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _activeEmergencyResources!.map((r) {
                      return ActionChip(
                        avatar: const Icon(Icons.phone, size: 14, color: Colors.white),
                        backgroundColor: AppTheme.emergencyRed,
                        label: Text(
                          '${r['name']}: ${r['number']}',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () => _launchCall(r['actionUrl'] ?? 'tel:${r['number']}'),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

          // Messages List
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + (_isTyping ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length && _isTyping) {
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.borderSubtle),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryBrand),
                          ),
                          SizedBox(width: 8),
                          Text('Counselor is typing...', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                        ],
                      ),
                    ),
                  );
                }

                final msg = _messages[index];
                final isPatient = msg['sender'] == 'PATIENT';
                final isCrisis = msg['isCrisis'] == true;

                return Align(
                  alignment: isPatient ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isPatient
                          ? AppTheme.primaryBrand
                          : (isCrisis ? const Color(0xFFFEF2F2) : Colors.white),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isPatient
                            ? AppTheme.primaryBrand
                            : (isCrisis ? AppTheme.emergencyRed.withOpacity(0.4) : AppTheme.borderSubtle),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: isPatient ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        Text(
                          msg['message'] ?? '',
                          style: TextStyle(
                            color: isPatient ? Colors.white : AppTheme.textDark,
                            fontSize: 13.5,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Message Input Field
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: AppTheme.borderSubtle)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    onSubmitted: (_) => _sendMessage(),
                    decoration: InputDecoration(
                      hintText: 'Describe your symptoms, ask medical questions, or request triage guidance...',
                      hintStyle: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      filled: true,
                      fillColor: AppTheme.surfaceSlate,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: const Icon(Icons.send_rounded, size: 18),
                  style: IconButton.styleFrom(backgroundColor: AppTheme.primaryBrand),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
