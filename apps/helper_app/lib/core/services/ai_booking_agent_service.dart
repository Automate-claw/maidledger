import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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
    final itemsList = response['items'] as List? ?? [];
    final items = itemsList
        .map((item) => item['item_name'] as String? ?? '')
        .where((name) => name.isNotEmpty)
        .toList();
    final itemRawTexts = itemsList
        .map((item) => item['item_raw_text'] as String? ?? '')
        .toList();

    // Workaround: the LLM sometimes ignores user-provided amounts (e.g. says 30
    // instead of 100). We extract all numeric amounts from raw text and use
    // the largest one as a fallback.
    double? amount = (response['total_amount'] as num?)?.toDouble();
    final rawAmounts = RegExp(r'\b(\d+(?:\.\d+)?)\s*(?:元|蚊|塊|\$|港幣|hk|HKD)?')
        .allMatches(text)
        .map((m) => double.tryParse(m.group(1)!))
        .whereType<double>()
        .toList();
    if (rawAmounts.isNotEmpty) {
      final maxFromRaw = rawAmounts.reduce((a, b) => a > b ? a : b);
      if (amount == null || amount == 0 || (amount != maxFromRaw && maxFromRaw > 0)) {
        amount = maxFromRaw;
      }
    }

    return ExpenseIntent(
      rawText: text,
      intent: _mapCategoryToIntent(response['store_cate'] ?? 'other'),
      category: response['store_cate'] as String? ?? 'other',
      amount: amount,
      confidence: (response['parse_confidence'] as num?)?.toDouble() ?? 0.5,
      items: items,
      itemRawTexts: itemRawTexts,
      note: response['reason'] as String?,
      fallback: completeness == 'partial',
      storeName: response['store_name'] as String?,
    );
  }

  Future<Map<String, dynamic>> _callEdgeLLM(String text, {String? userId}) async {
    debugPrint('🤖 [AIBookingAgent] Calling edge function with text: $text');

    final bodyBytes = utf8.encode(jsonEncode({'text': text, 'user_id': userId ?? 'anonymous'}));

    final resp = await http.post(
      Uri.parse(_edgeUrl),
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhueWF6ZnJrenB4ZGppeWZ6ZW1tIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg2NTUwMjcsImV4cCI6MjA5NDIzMTAyN30.lo2HAv0E9WK1CRHTtU3idlrq3xNogdUAbWfpXvz90J0',
      },
      body: bodyBytes,
    ).timeout(const Duration(seconds: 60));

    debugPrint('🤖 [AIBookingAgent] Edge response status: ${resp.statusCode}');
    debugPrint('🤖 [AIBookingAgent] Edge response body: ${resp.body}');

    if (resp.statusCode != 200) {
      debugPrint('🤖 [AIBookingAgent] Error response code: ${resp.statusCode}');
      throw Exception('Edge function error: ${resp.body}');
    }

    return jsonDecode(resp.body) as Map<String, dynamic>;
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
  final List<String> items;  // item_name list (ideally translated by LLM)
  final List<String> itemRawTexts;  // per-item raw text from LLM
  final String? note;
  final bool fallback;
  final bool isRejected;
  final String? rejectionReason;
  final String? storeName;

  ExpenseIntent({
    required this.rawText,
    required this.intent,
    this.category,
    this.amount,
    required this.confidence,
    this.items = const [],
    this.itemRawTexts = const [],
    this.note,
    this.fallback = false,
    this.isRejected = false,
    this.rejectionReason,
    this.storeName,
  });
}