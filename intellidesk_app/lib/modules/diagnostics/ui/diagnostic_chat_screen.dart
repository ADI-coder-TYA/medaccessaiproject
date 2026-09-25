import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../../../config/api_config.dart';
import '../../../providers/auth_provider.dart';

// ── Data model ────────────────────────────────────────────────────
class _ChatMsg {
  final String text;
  final bool isUser;
  final DateTime ts;
  final bool isCrisis;

  const _ChatMsg({
    required this.text,
    required this.isUser,
    required this.ts,
    this.isCrisis = false,
  });
}

// ── Role used by backend history ──────────────────────────────────
class _HistoryEntry {
  final String role; // 'user' | 'model'
  final String text;
  const _HistoryEntry(this.role, this.text);

  Map<String, String> toJson() => {'role': role, 'text': text};
}

// ─────────────────────────────────────────────────────────────────
class DiagnosticChatScreen extends StatefulWidget {
  const DiagnosticChatScreen({super.key});

  @override
  State<DiagnosticChatScreen> createState() => _DiagnosticChatScreenState();
}

class _DiagnosticChatScreenState extends State<DiagnosticChatScreen>
    with TickerProviderStateMixin {
  final List<_ChatMsg> _messages = [];
  final List<_HistoryEntry> _history = [];
  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _isTyping = false;

  late AnimationController _dotAnim;

  static const _teal = Color(0xFF0D9488);
  static const _tealLight = Color(0xFF5EEAD4);
  static const _bg = Color(0xFF0F172A);
  static const _surface = Color(0xFF1E293B);
  static const _surfaceHigh = Color(0xFF334155);

  @override
  void initState() {
    super.initState();
    _dotAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      final name = auth.user?.name.split(' ').first ?? 'there';
      _addBotMessage(
        'Hi $name! I\'m Aria, your personal mental health counsellor here at MedAccess. '
        'I\'m here to listen, support, and talk through anything on your mind — whether it\'s '
        'stress, anxiety, your health, or just how you\'re feeling today. '
        'What would you like to talk about?',
      );
    });
  }

  @override
  void dispose() {
    _dotAnim.dispose();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _addBotMessage(String text, {bool isCrisis = false}) {
    setState(() {
      _messages.add(_ChatMsg(text: text, isUser: false, ts: DateTime.now(), isCrisis: isCrisis));
    });
    _scrollToBottom();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _isTyping) return;

    _ctrl.clear();
    setState(() {
      _messages.add(_ChatMsg(text: text, isUser: true, ts: DateTime.now()));
      _history.add(_HistoryEntry('user', text));
      _isTyping = true;
    });
    _scrollToBottom();

    final auth = context.read<AuthProvider>();
    final patientId = auth.user?.patientId ?? auth.user?.id ?? 'anonymous';

    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/chat/mental-health');
      final body = jsonEncode({
        'patientId': patientId,
        'message': text,
        'history': _history
            .sublist(0, (_history.length - 1).clamp(0, _history.length - 1))
            .map((h) => h.toJson())
            .toList(),
      });

      final resp = await http
          .post(uri,
              headers: ApiConfig.patientHeaders,
              body: body)
          .timeout(const Duration(seconds: 30));

      if (!mounted) return;

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final reply = (data['reply'] as String? ?? '').trim();
        final isCrisis = data['isCrisis'] == true;

        _history.add(_HistoryEntry('model', reply));

        setState(() {
          _isTyping = false;
          _messages.add(_ChatMsg(text: reply, isUser: false, ts: DateTime.now(), isCrisis: isCrisis));
        });
        _scrollToBottom();

        if (isCrisis) _showCrisisSheet(data['resources']);
      } else {
        _handleError('Server error (${resp.statusCode}). Please try again.');
      }
    } catch (e) {
      _handleError('Could not reach Aria right now. Please check your connection.');
    }
  }

  void _handleError(String msg) {
    if (!mounted) return;
    setState(() => _isTyping = false);
    _addBotMessage(msg);
  }

  void _showCrisisSheet(dynamic resources) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) {
        final list = resources is List ? resources : [];
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.crisis_alert, color: Colors.redAccent, size: 28),
                const SizedBox(width: 10),
                const Expanded(
                    child: Text('Crisis Support Lines',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold))),
              ]),
              const SizedBox(height: 16),
              ...list.map<Widget>((r) {
                final name = r['name'] ?? '';
                final number = r['number'] ?? '';
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                      backgroundColor: Colors.redAccent,
                      child: Icon(Icons.phone, color: Colors.white, size: 18)),
                  title: Text(name,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  subtitle: Text(number,
                      style: const TextStyle(color: _tealLight, fontSize: 13)),
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Build ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: _bg,
        colorScheme: ColorScheme.dark(primary: _teal, surface: _surface),
      ),
      child: Scaffold(
        backgroundColor: _bg,
        appBar: _buildAppBar(),
        body: Column(
          children: [
            Expanded(child: _buildMessageList()),
            if (_isTyping) _buildTypingIndicator(),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _surface,
      elevation: 0,
      leading: BackButton(color: Colors.white70),
      titleSpacing: 0,
      title: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [_teal, Color(0xFF14B8A6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                    color: _teal.withValues(alpha: 0.4), blurRadius: 8, offset: const Offset(0, 2)),
              ],
            ),
            child: const Icon(Icons.spa_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Aria',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.3)),
              Text('Mental Health Counsellor · MedAccess',
                  style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
            ],
          ),
        ],
      ),
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 16),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _teal.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _teal.withValues(alpha: 0.4)),
          ),
          child: const Row(
            children: [
              Icon(Icons.circle, color: Color(0xFF4ADE80), size: 8),
              SizedBox(width: 5),
              Text('Online',
                  style: TextStyle(color: Color(0xFF4ADE80), fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMessageList() {
    if (_messages.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: _teal, strokeWidth: 2),
      );
    }

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      itemCount: _messages.length,
      itemBuilder: (ctx, i) => _buildBubble(_messages[i]),
    );
  }

  Widget _buildBubble(_ChatMsg msg) {
    final isUser = msg.isUser;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            _ariaAvatar(),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.76),
                  decoration: BoxDecoration(
                    gradient: isUser
                        ? const LinearGradient(
                            colors: [Color(0xFF0D9488), Color(0xFF0F766E)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: isUser ? null : _surfaceHigh,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isUser ? 18 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 18),
                    ),
                    border: msg.isCrisis
                        ? Border.all(color: Colors.redAccent.withValues(alpha: 0.7), width: 1.5)
                        : (!isUser
                            ? Border.all(color: _teal.withValues(alpha: 0.15), width: 0.8)
                            : null),
                    boxShadow: [
                      BoxShadow(
                          color: (isUser ? _teal : Colors.black).withValues(alpha: 0.15),
                          blurRadius: 6,
                          offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Text(
                    msg.text,
                    style: TextStyle(
                      color: isUser ? Colors.white : const Color(0xFFE2E8F0),
                      fontSize: 14.5,
                      height: 1.55,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _formatTime(msg.ts),
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 10.5),
                ),
              ],
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _ariaAvatar() {
    return Container(
      width: 30,
      height: 30,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [_teal, Color(0xFF14B8A6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Icon(Icons.spa_rounded, color: Colors.white, size: 16),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
      child: Row(
        children: [
          _ariaAvatar(),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _surfaceHigh,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _teal.withValues(alpha: 0.2)),
            ),
            child: AnimatedBuilder(
              animation: _dotAnim,
              builder: (context2, child2) => Row(
                children: List.generate(3, (i) {
                  final offset = (i * 0.33);
                  final val = ((_dotAnim.value + offset) % 1.0);
                  final opacity = (val < 0.5 ? val * 2 : (1 - val) * 2).clamp(0.3, 1.0);
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _teal.withValues(alpha: opacity),
                    ),
                  );
                }),
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Text('Aria is typing…',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: _surface,
        border: Border(top: BorderSide(color: _teal.withValues(alpha: 0.15))),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, -2)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: TextField(
                  controller: _ctrl,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 14.5),
                  decoration: InputDecoration(
                    hintText: 'Share what\'s on your mind…',
                    hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 14),
                    fillColor: _surfaceHigh,
                    filled: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: const BorderSide(color: _teal, width: 1.5),
                    ),
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _send,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: _isTyping
                      ? const LinearGradient(
                          colors: [Color(0xFF334155), Color(0xFF475569)])
                      : const LinearGradient(
                          colors: [_teal, Color(0xFF0F766E)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                  boxShadow: _isTyping
                      ? []
                      : [
                          BoxShadow(
                              color: _teal.withValues(alpha: 0.4),
                              blurRadius: 10,
                              offset: const Offset(0, 3))
                        ],
                ),
                child: Icon(
                  _isTyping ? Icons.hourglass_top_rounded : Icons.send_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
