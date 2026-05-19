import 'package:http/http.dart' as http;
import 'dart:convert';

/// AI Booking Agent
/// Multi-language conversational expense entry
/// Uses keyword engine + Gemini 1.5 Flash for intent detection
class AIBookingAgent {
  final String _geminiApiKey;
  final String _translateApiKey;

  // Keyword triggers for common expense intents
  static const _keywordIntents = {
    'buy': ['買', '买', 'bought', 'bili', 'bought', 'bayar', 'bili', 'shopping'],
    'food': ['食', '吃', 'eat', 'food', 'makan', 'kain', 'rice', 'dinner', 'lunch'],
    'transport': ['車', '车', 'bus', 'taxi', 'MTR', '地鐵', '地铁', ' jeep '],
    'market': ['街市', 'market', 'wet market', '菜市場', '菜市场', 'pasar'],
    'supermarket': ['超市', 'supermarket', '惠康', '百佳', 'HKTV', '屈臣氏'],
    'confirm': ['係', '是', 'yes', 'correct', 'right', 'ok', '好', 'okay'],
    'cancel': ['唔好', '不要', 'no', 'cancel', 'wrong', '錯', '错'],
  };

  // Language codes
  static const _langCodes = {
    'zh': 'zh-Hant',
    'en': 'en',
    'tl': 'tl',  // Tagalog/Filipino
    'id': 'id',  // Indonesian
    'my': 'my',  // Burmese
  };

  AIBookingAgent({
    required String geminiApiKey,
    required String translateApiKey,
  })  : _geminiApiKey = geminiApiKey,
        _translateApiKey = translateApiKey;

  /// Detect language from input text
  Future<String> detectLanguage(String text) async {
    // Simple heuristic-based detection
    // In production, use Google ML Kit Language Detection
    final hasChinese = RegExp(r'[\u4e00-\u9fff]').hasMatch(text);
    final hasTagalog = RegExp(
      r'(ang|ng|sa|ko|mo|ay|mga|siya|kami|kayo|sila)',
      caseSensitive: false,
    ).hasMatch(text);

    if (hasChinese) return 'zh';
    if (hasTagalog) return 'tl';
    return 'en'; // Default to English
  }

  /// Parse user input into structured expense
  Future<ExpenseIntent> parseExpense(String text) async {
    // First try keyword-based detection (free, fast)
    final keywordResult = _detectFromKeywords(text.toLowerCase());
    if (keywordResult.confidence > 0.85) {
      return keywordResult;
    }

    // Fall back to Gemini for complex queries
    return await _parseWithGemini(text);
  }

  /// Keyword-based intent detection
  ExpenseIntent _detectFromKeywords(String text) {
    double maxConfidence = 0.0;
    String? detectedIntent;
    double? amount;
    String? category;

    // Check each intent category
    for (final entry in _keywordIntents.entries) {
      for (final keyword in entry.value) {
        if (text.contains(keyword.toLowerCase())) {
          if (entry.key == 'supermarket' || entry.key == 'market') {
            category = 'food'; // Default to food for market visits
          } else {
            category = entry.key;
          }
          maxConfidence = 0.9;
          detectedIntent = entry.key;
          break;
        }
      }
      if (maxConfidence > 0.85) break;
    }

    // Extract amount if present
    final amountMatch = RegExp(r'\$?\s*(\d+(?:\.\d{1,2})?)\s*(?:蚊|元|塊|块|港幣|港币|HKD| dollars?|dollars?|pesos?|PHP)?', caseSensitive: false)
        .firstMatch(text);
    if (amountMatch != null) {
      amount = double.tryParse(amountMatch.group(1)!);
    }

    return ExpenseIntent(
      rawText: text,
      intent: detectedIntent ?? 'unknown',
      confidence: maxConfidence,
      amount: amount,
      category: category,
      fallback: maxConfidence < 0.85,
    );
  }

  /// Use Gemini 1.5 Flash for complex parsing
  Future<ExpenseIntent> _parseWithGemini(String text) async {
    final lang = await detectLanguage(text);

    final prompt = '''
Parse this expense input from a foreign domestic worker.
Input: "$text"
Language detected: $lang

Respond in JSON format:
{
  "intent": "buy|food|transport|market|supermarket|unknown",
  "category": "food|transport|household|other",
  "amount": number or null,
  "confidence": 0.0-1.0,
  "items": ["item1", "item2"] or [],
  "note": "any additional context"
}

Rules:
- If amount is not mentioned, set amount to null
- category should be one of: food, transport, household, other
- intent "buy" is generic purchase, map to appropriate category
''';

    try {
      final response = await http.post(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$_geminiApiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [{'parts': [{'text': prompt}]}],
          'generationConfig': {'temperature': 0.3, 'maxOutputTokens': 200},
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final textResponse = data['candidates']?[0]?['content']?['parts']?[0]?['text'] ?? '';

        // Extract JSON from response
        final jsonMatch = RegExp(r'\{.*\}', dotAll: true).firstMatch(textResponse);
        if (jsonMatch != null) {
          final parsed = jsonDecode(jsonMatch.group(0)!);
          return ExpenseIntent(
            rawText: text,
            intent: parsed['intent'] ?? 'unknown',
            category: parsed['category'] ?? 'other',
            amount: parsed['amount']?.toDouble(),
            confidence: (parsed['confidence'] ?? 0.5).toDouble(),
            items: List<String>.from(parsed['items'] ?? []),
            note: parsed['note'],
            fallback: false,
          );
        }
      }
    } catch (e) {
      // Fall back to keyword engine
    }

    return ExpenseIntent(
      rawText: text,
      intent: 'unknown',
      confidence: 0.0,
      fallback: true,
    );
  }

  /// Build conversation response
  String buildResponse(ExpenseIntent intent) {
    if (intent.fallback) {
      return '🤖 我不太確定你想記帳什麼。你可以試試：\n'
          '• "買咗菜 45 蚊" \n'
          '• "超市 $50" \n'
          '• "街市買魚 80"';
    }

    final amountStr = intent.amount != null ? '\$${intent.amount!.toStringAsFixed(0)}' : '';
    final categoryEmoji = _getCategoryEmoji(intent.category);

    return '$categoryEmoji 已記帳：$amountStr\n'
        '類別：${_getCategoryName(intent.category)}\n'
        '確認？ ✅ / ❌';
  }

  String _getCategoryEmoji(String category) {
    switch (category) {
      case 'food': return '🥬';
      case 'transport': return '🚌';
      case 'household': return '🏠';
      default: return '📝';
    }
  }

  String _getCategoryName(String category) {
    switch (category) {
      case 'food': return '食物';
      case 'transport': return '交通';
      case 'household': return '家居';
      default: return '其他';
    }
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

  ExpenseIntent({
    required this.rawText,
    required this.intent,
    this.category,
    this.amount,
    required this.confidence,
    this.items = const [],
    this.note,
    this.fallback = false,
  });
}