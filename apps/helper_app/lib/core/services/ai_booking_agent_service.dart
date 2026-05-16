import 'dart:convert';
import 'dart:io';

/// AI Booking Agent
/// Multi-language conversational expense entry
/// Routes through Supabase Edge Function → OpenRouter (DeepSeek V4)
/// Strict 2-stage classification: is_expense check + completeness assessment
class AIBookingAgent {
  static const _edgeUrl =
      'https://hnyazfrkzpxdjiyfzemm.supabase.co/functions/v1/chat-parser';

  /// Parse user input into structured expense
  /// [userId] is passed for rate limiting
  Future<ExpenseIntent> parseExpense(String text, {String? userId}) async {
    final response = await _callEdgeLLM(text, userId: userId);

    if (response['error'] != null) {
      throw Exception(response['error']);
    }

    // Stage 1: Check if it's even an expense
    final isExpense = response['is_expense'] as bool? ?? false;
    if (!isExpense) {
      // Use friendly response_message from edge function (never show error)
      final responseMsg = response['response_message'] as String?;
      if (responseMsg != null) {
        return ExpenseIntent(
          rawText: text,
          intent: 'chat',
          category: null,
          amount: null,
          confidence: 0.0,
          items: [],
          note: responseMsg,
          fallback: false,
          isRejected: false,
        );
      }
      final reason = response['reason'] as String? ?? '請輸入開支資料';
      return _rejectionIntent(reason);
    }

    // Stage 2: Check completeness
    final completeness = response['completeness'] as String? ?? 'invalid';
    if (completeness == 'insufficient') {
      final reason = response['reason'] as String? ?? '資料不足，請提供更多詳細';
      return _rejectionIntent(reason);
    }

    // Stage 3: Map successful parse to ExpenseIntent
    final items = (response['items'] as List? ?? [])
        .map((item) => item['item_name'] as String? ?? '')
        .where((name) => name.isNotEmpty)
        .toList();

    return ExpenseIntent(
      rawText: text,
      intent: _mapCategoryToIntent(response['store_cate'] ?? 'other'),
      category: response['store_cate'] as String? ?? 'other',
      amount: (response['total_amount'] as num?)?.toDouble(),
      confidence: (response['parse_confidence'] as num?)?.toDouble() ?? 0.5,
      items: items,
      note: response['reason'] as String?,
      fallback: completeness == 'partial',
    );
  }

  Future<Map<String, dynamic>> _callEdgeLLM(String text, {String? userId}) async {
    final uri = Uri.parse(_edgeUrl);
    final req = await HttpClient().postUrl(uri);

    req.headers.set('Content-Type', 'application/json');
    req.headers.set(
        'apikey',
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJl'
            'ZiI6ImhueWF6ZnJrenB4ZGppeWZ6ZW1tIiwicm9sZSI6ImFub24iLCJpYXQiOjE3'
            'Nzg2NTUwMjcsImV4cCI6MjA5NDIzMTAyN30.lo2HAv0E9WK1CRHTtU3idlrq3'
            'xNogdUAbWfpXvz90J0');

    final body = jsonEncode({'text': text, 'user_id': userId ?? 'anonymous'});
    req.write(body);

    final resp = await req.close();
    final respStr = await resp.transform(utf8.decoder).join();

    if (resp.statusCode != 200) {
      throw Exception('Edge function error: $respStr');
    }

    return jsonDecode(respStr) as Map<String, dynamic>;
  }

  /// Create a rejection intent (is_expense=false or insufficient)
  ExpenseIntent _rejectionIntent(String reason) {
    return ExpenseIntent(
      rawText: reason,
      intent: 'rejected',
      category: null,
      amount: null,
      confidence: 0.0,
      items: [],
      note: reason,
      fallback: true,
      isRejected: true,
      rejectionReason: reason,
    );
  }

  String _mapCategoryToIntent(String storeCate) {
    switch (storeCate) {
      case 'wet_market':
        return 'market';
      case 'supermarket':
        return 'supermarket';
      case 'restaurant':
      case 'cafe':
      case 'takeaway':
        return 'food';
      default:
        return 'buy';
    }
  }

  /// Build conversation response
  String buildResponse(ExpenseIntent intent) {
    // Handle chat/non-expense response (friendly guidance, not error)
    if (intent.intent == 'chat') {
      return intent.note ?? '請告訴我你想記帳的內容，例如：魚 30蚊';
    }

    // Handle rejection (insufficient data)
    if (intent.isRejected) {
      return '📋 ${intent.rejectionReason}\n\n'
          '請輸入開支格式，例如：\n'
          '• 魚 30蚊\n'
          '• 紅衫魚 1斤 40元\n'
          '• 超市 買餸 \$120';
    }

    // Handle partial (low confidence but saveable)
    if (intent.fallback) {
      final amountStr =
          intent.amount != null ? '\$${intent.amount!.toStringAsFixed(0)}' : '';
      return '📝 已記帳（請確認）：\n'
          '項目：${intent.items.join('、')}\n'
          '金額：$amountStr\n'
          '信心度：${(intent.confidence * 100).toInt()}%（較低，請確認）\n\n'
          '確認儲存？ ✅ / ❌';
    }

    // Full success
    final amountStr =
        intent.amount != null ? '\$${intent.amount!.toStringAsFixed(0)}' : '';
    final itemsStr =
        intent.items.isNotEmpty ? intent.items.join('、') : '其他';

    return '📋 已分析：\n'
        '項目：$itemsStr\n'
        '金額：$amountStr\n'
        '類別：${intent.category ?? "other"}\n'
        '信心度：${(intent.confidence * 100).toInt()}%\n\n'
        '確認儲存？ ✅ / ❌';
  }
}

class ExpenseIntent {
  final String rawText;
  final String intent;
  final String? category;
  final double? amount;
  final double confidence;
  final List<String> items;
  final String? note;
  final bool fallback;
  final bool isRejected;
  final String? rejectionReason;

  ExpenseIntent({
    required this.rawText,
    required this.intent,
    this.category,
    this.amount,
    required this.confidence,
    this.items = const [],
    this.note,
    this.fallback = false,
    this.isRejected = false,
    this.rejectionReason,
  });
}