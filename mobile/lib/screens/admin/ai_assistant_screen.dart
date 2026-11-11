import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_theme.dart';
import '../../providers/app_provider.dart';
import '../../services/chat_service.dart';

/// Standalone push route for the SCOPED case only — "Ask AI about this user"
/// from a user's detail page. The unscoped, whole-company assistant lives as
/// an embedded bottom-nav tab in AdminHomeScreen instead (see AiAssistantView
/// below), so it doesn't need its own Scaffold/AppBar there.
class AiAssistantScreen extends StatelessWidget {
  final int? scopedUserId;
  final String? scopedUsername;

  const AiAssistantScreen({super.key, this.scopedUserId, this.scopedUsername});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          scopedUsername != null ? 'Ask about $scopedUsername' : 'AI Assistant',
        ),
      ),
      body: SafeArea(
        child: AiAssistantView(
          scopedUserId: scopedUserId,
          scopedUsername: scopedUsername,
        ),
      ),
    );
  }
}

/// The assistant's actual chat UI, with no Scaffold/AppBar of its own — used
/// both by [AiAssistantScreen] (wrapped, for the scoped push-route case) and
/// directly as a tab body in AdminHomeScreen (unscoped, where the shared
/// AppBar already shows the "AI Assistant" title).
class AiAssistantView extends StatefulWidget {
  final int? scopedUserId;
  final String? scopedUsername;

  const AiAssistantView({super.key, this.scopedUserId, this.scopedUsername});

  @override
  State<AiAssistantView> createState() => _AiAssistantViewState();
}

class _AiAssistantViewState extends State<AiAssistantView> {
  late final ChatService _chat;
  final _input = TextEditingController();
  final _scrollController = ScrollController();
  final List<_Message> _messages = [];
  bool? _configured;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _chat = context.read<AppProvider>().chatService;
    _checkConfigured();
  }

  Future<void> _checkConfigured() async {
    try {
      final ok = await _chat.isConfigured();
      if (mounted) setState(() => _configured = ok);
    } catch (_) {
      if (mounted) setState(() => _configured = false);
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _messages.add(_Message(role: 'user', text: text));
      _sending = true;
    });
    _input.clear();
    _scrollToBottom();

    try {
      final history = _messages
          .where((m) => m.text.isNotEmpty)
          .map((m) => ChatTurn(role: m.role, content: m.text))
          .toList();
      // Exclude the message we just added locally — server gets it as `message`.
      final priorHistory = history.length > 1
          ? history.sublist(0, history.length - 1)
          : <ChatTurn>[];

      final reply = await _chat.ask(
        text,
        scopedUserId: widget.scopedUserId,
        history: priorHistory,
      );
      setState(() => _messages.add(_Message(role: 'assistant', text: reply)));
    } catch (e) {
      setState(
        () => _messages.add(
          _Message(
            role: 'assistant',
            text: 'Sorry, could not reach the assistant: $e',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return _configured == null
        ? const Center(child: CircularProgressIndicator())
        : !_configured!
        ? const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text(
                "The AI Assistant isn't set up yet — an administrator needs to add an API key first.",
                textAlign: TextAlign.center,
              ),
            ),
          )
        : Column(
            children: [
              Expanded(
                child: _messages.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            widget.scopedUsername != null
                                ? 'Ask anything about ${widget.scopedUsername}\'s attendance, reports, or check-in history.'
                                : 'Ask about any employee\'s attendance, reports, or check-in history.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (context, i) =>
                            _Bubble(message: _messages[i]),
                      ),
              ),
              if (_sending) const LinearProgressIndicator(minHeight: 2),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        decoration: const InputDecoration(
                          hintText: 'Ask a question...',
                        ),
                        onSubmitted: (_) => _send(),
                        enabled: !_sending,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _sending ? null : _send,
                      icon: const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ),
            ],
          );
  }
}

class _Message {
  final String role;
  final String text;
  _Message({required this.role, required this.text});
}

class _Bubble extends StatelessWidget {
  final _Message message;
  const _Bubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final color = isUser ? Colors.white : AppColors.ink;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: isUser ? AppColors.primary : AppColors.primarySoft,
          borderRadius: BorderRadius.circular(16),
        ),
        // The assistant's own replies are trusted markdown (from our backend,
        // not arbitrary user input) — the user's own typed message never goes
        // through this, so it's shown as plain text (isUser skips formatting).
        child: isUser
            ? Text(message.text, style: TextStyle(color: color))
            : _formatMarkdown(message.text, color),
      ),
    );
  }

  /// Renders the small subset of markdown Gemini's replies actually use:
  /// **bold** spans and "* "/"- " bullet lines. Not a general markdown
  /// parser — just enough that replies read as formatted text instead of
  /// showing literal asterisks.
  Widget _formatMarkdown(String text, Color color) {
    final baseStyle = TextStyle(color: color);
    final lines = text.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < lines.length; i++) ...[
          if (i > 0) const SizedBox(height: 4),
          _formatLine(lines[i], baseStyle),
        ],
      ],
    );
  }

  Widget _formatLine(String line, TextStyle baseStyle) {
    final bulletMatch = RegExp(r'^(\*|-)\s+(.*)$').firstMatch(line);
    final content = bulletMatch?.group(2) ?? line;
    final spans = _parseBoldSpans(content, baseStyle);

    if (bulletMatch != null) {
      return Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('•  ', style: baseStyle),
            Expanded(
              child: RichText(text: TextSpan(children: spans)),
            ),
          ],
        ),
      );
    }
    return RichText(text: TextSpan(children: spans));
  }

  List<TextSpan> _parseBoldSpans(String text, TextStyle baseStyle) {
    final spans = <TextSpan>[];
    final pattern = RegExp(r'\*\*(.+?)\*\*');
    var lastEnd = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(
          TextSpan(
            text: text.substring(lastEnd, match.start),
            style: baseStyle,
          ),
        );
      }
      spans.add(
        TextSpan(
          text: match.group(1),
          style: baseStyle.copyWith(fontWeight: FontWeight.bold),
        ),
      );
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd), style: baseStyle));
    }
    return spans;
  }
}
