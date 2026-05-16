import 'package:http/http.dart' as http;
import 'dart:convert';

/// Receipt Parser Service
/// Uses Gemini to parse raw OCR text into structured receipt data
class ReceiptParserService {
  final String _geminiApiKey;

  ReceiptParserService({required String geminiApiKey})
      : _geminiApiKey = geminiApiKey;

  /// Parse raw OCR text into structured receipt data
  Future<ReceiptParseResult> parseReceiptText(String rawText) async {
    if (rawText.trim().isEmpty) {
      return ReceiptParseResult.failed('Empty text input');
    }

    final prompt = '''
你係一個香港超市/街市收據分析助手。請分析以下OCR文字，提取結構化資料。

OCR原始文字：
"""
$rawText
"""

請以繁體中文輸出以下JSON格式（只輸出JSON，唔好其他解釋）：

{
  "store_name": "店舖名稱，例如：惠康、百佳、錢大媽、濕貨街市檔",
  "store_cate": "supermarket|wet_market|pharmacy|convenience|online|other",
  "location": "地區或地址，例如：元朗、觀塘、將軍澳",
  "total_amount": 總金額（數字，例如：123.5），如果搵唔到就null,
  "transaction_date": "交易日期（YYYY-MM-DD格式），如果搵唔到就null",
  "items": [
    {
      "item_name": "產品名稱",
      "item_raw_text": "呢行嘅原始OCR文字",
      "qty": 數量（數字，預設1）,
      "unit_price": 單價（數字，例如：12.5），如果搵唔到就null,
      "prd_cate": "fish|pork|beef|chicken|vegetables|rice|oil|seasoning|snack|drink|daily|other"
    }
  ],
  "parse_confidence": 0.0-1.0，反映整體解析可信程度
}

規則：
- 金額單位係港幣（HKD）
- 如果係超市，尽量识别store_name（如惠康、百佳、AEON、華潤、U購等）
- 街市檔就盡量搵具體品名同價格
- items必須係陣列，每個產品一項，唔好夾雜總額、行數等
- 如果某個欄位完全搵唔到，設為null
- prd_cate參考：fish=魚/海鮮, pork=豬肉, beef=牛肉, chicken=雞肉, vegetables=蔬菜, rice=米, oil=油, seasoning=調味, snack=零食, drink=飲料, daily=日用品, other=其他
- 解析失敗或完全不確定時，整個items可以係空陣列，但其他基本欄位盡量填
''';

    try {
      final response = await http.post(
        Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$_geminiApiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [{'parts': [{'text': prompt}]}],
          'generationConfig': {
            'temperature': 0.2,
            'maxOutputTokens': 2048,
          },
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final textResponse =
            data['candidates']?[0]?['content']?['parts']?[0]?['text'] ?? '';

        return _parseGeminiResponse(textResponse, rawText);
      } else {
        return ReceiptParseResult.failed(
            'Gemini API error: ${response.statusCode}');
      }
    } catch (e) {
      return ReceiptParseResult.failed('Network error: $e');
    }
  }

  ReceiptParseResult _parseGeminiResponse(String textResponse, String rawText) {
    try {
      // Extract JSON from response (may be wrapped in markdown code blocks)
      final jsonMatch = RegExp(r'\{[\s\S]*\}', dotAll: true).firstMatch(textResponse);

      if (jsonMatch == null) {
        return ReceiptParseResult.failed('No JSON found in Gemini response');
      }

      final parsed = jsonDecode(jsonMatch.group(0)!);

      final items = (parsed['items'] as List? ?? [])
          .map((item) => ParsedItem(
                itemName: item['item_name'] ?? '',
                itemRawText: item['item_raw_text'] ?? '',
                qty: (item['qty'] ?? 1).toDouble(),
                unitPrice: item['unit_price']?.toDouble(),
                prdCate: item['prd_cate'] ?? 'other',
              ))
          .where((item) => item.itemName.isNotEmpty)
          .toList();

      return ReceiptParseResult(
        storeName: parsed['store_name'],
        storeCate: parsed['store_cate'] ?? 'other',
        location: parsed['location'],
        totalAmount: parsed['total_amount']?.toDouble(),
        transactionDate: parsed['transaction_date'],
        items: items,
        parseConfidence: (parsed['parse_confidence'] ?? 0.5).toDouble(),
        rawText: rawText,
        isSuccess: true,
      );
    } catch (e) {
      return ReceiptParseResult.failed('JSON parse error: $e');
    }
  }
}

/// Result of receipt parsing
class ReceiptParseResult {
  final String? storeName;
  final String storeCate;
  final String? location;
  final double? totalAmount;
  final String? transactionDate;
  final List<ParsedItem> items;
  final double parseConfidence;
  final String rawText;
  final bool isSuccess;
  final String? errorMessage;

  ReceiptParseResult({
    this.storeName,
    this.storeCate = 'other',
    this.location,
    this.totalAmount,
    this.transactionDate,
    this.items = const [],
    this.parseConfidence = 0.0,
    required this.rawText,
    this.isSuccess = true,
    this.errorMessage,
  });

  factory ReceiptParseResult.failed(String error) {
    return ReceiptParseResult(
      isSuccess: false,
      errorMessage: error,
      rawText: '',
    );
  }

  /// Create from a failed parse (e.g., OCR returned empty)
  factory ReceiptParseResult.empty() => ReceiptParseResult(rawText: '');

  bool get hasItems => items.isNotEmpty;
}

/// A single parsed item from receipt
class ParsedItem {
  final String itemName;
  final String itemRawText;
  final double qty;
  final double? unitPrice;
  final String prdCate;

  ParsedItem({
    required this.itemName,
    required this.itemRawText,
    this.qty = 1.0,
    this.unitPrice,
    this.prdCate = 'other',
  });

  double? get lineTotal =>
      (unitPrice != null && qty > 0) ? unitPrice! * qty : null;

  Map<String, dynamic> toMap(String receiptId) => {
        'receipt_id': receiptId,
        'item_name': itemName,
        'item_raw_text': itemRawText,
        'qty': qty,
        'unit_price': unitPrice,
        'prd_cate': prdCate,
        'line_total': lineTotal,
      };
}