import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/supabase_client_provider.dart';
import '../../core/services/ai_booking_agent_service.dart';

/// Chat screen for AI-powered expense entry
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isTyping = false;

  late final AIBookingAgent _agent;

  @override
  void initState() {
    super.initState();
    _agent = AIBookingAgent(
      geminiApiKey: const String.fromEnvironment('GEMINI_API_KEY'),
      translateApiKey: '',
    );

    _messages.add(const ChatMessage(
      text: '👋 你好！用任何語言告訴我你想記帳的內容。\n\n'
          '例如：\n'
          '• "買咗菜 45 蚊"\n'
          '• "超市 50"\n'
          '• "街市買魚 80"',
      isUser: false,
    ));
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();

    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _isTyping = true;
    });

    _scrollToBottom();

    try {
      final intent = await _agent.parseExpense(text);
      final response = _agent.buildResponse(intent);

      setState(() {
        _messages.add(ChatMessage(
          text: response,
          isUser: false,
          data: intent,
        ));
        _isTyping = false;
      });

      _scrollToBottom();

      if (intent.confidence > 0.7 && intent.amount != null) {
        _showSaveDialog(intent);
      }
    } catch (e) {
      setState(() {
        _messages.add(const ChatMessage(
          text: '⚠️ 抱歉，我遇到問題了。請再試一次。',
          isUser: false,
        ));
        _isTyping = false;
      });
    }
  }

  void _showSaveDialog(ExpenseIntent intent) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('💾 儲存記帳？'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('類別：${intent.category ?? "未知"}'),
            if (intent.amount != null)
              Text('金額：\$${intent.amount!.toStringAsFixed(0)}'),
            Text('信心度：${(intent.confidence * 100).toInt()}%'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _saveExpense(intent);
            },
            child: const Text('儲存'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveExpense(ExpenseIntent intent) async {
    try {
      final client = supabase;
      final now = DateTime.now().millisecondsSinceEpoch;

      await client.from('receipts').insert({
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'raw_text': intent.rawText,
        'parsed_data': {
          'intent': intent.intent,
          'category': intent.category,
          'amount': intent.amount,
        },
        'category': intent.category,
        'amount': intent.amount,
        'sync_status': 'pending',
        'local_timestamp': now,
        'created_at': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ 記帳已保存！'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ 保存失敗：$e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 記帳助理'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _messages.clear();
                _messages.add(const ChatMessage(
                  text: '👋 你好！用任何語言告訴我你想記帳的內容。',
                  isUser: false,
                ));
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return ChatBubble(message: message);
              },
            ),
          ),
          if (_isTyping)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Row(
                children: [
                  Text('🤖 ', style: TextStyle(fontSize: 14)),
                  SizedBox(width: 8),
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('AI 正在思考...'),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: '輸入記帳內容...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton.filled(
                    onPressed: _isTyping ? null : _sendMessage,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final ExpenseIntent? data;

  const ChatMessage({
    required this.text,
    required this.isUser,
    this.data,
  });
}

class ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: message.isUser
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(message.isUser ? 16 : 4),
            bottomRight: Radius.circular(message.isUser ? 4 : 16),
          ),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: message.isUser ? Colors.white : null,
          ),
        ),
      ),
    );
  }
}