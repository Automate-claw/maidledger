import 'dart:convert';
import 'dart:io';
import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:exif/exif.dart';
import 'package:maidledger_localization/maidledger_localization.dart';
import '../../core/services/supabase_client_provider.dart';
import '../../core/services/ai_booking_agent_service.dart';
import '../../core/services/shop_matching_service.dart';
import '../../core/services/location_service.dart';
import '../../core/services/receipt_scanner_service.dart';

/// Chat screen for AI-powered expense entry
/// Supports: text input + optional image attachment + EXIF location
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

  // Attached image state
  XFile? _attachedImage;
  String? _extractedLocation;
  bool _isExtractingLocation = false; // blocks send until location is ready
  String? _attachedImageBase64; // for reliable display

  // Buffer for save dialog (needed because dialog outlives _sendMessage scope)
  XFile? _pendingImage;
  String? _pendingLocation;
  String? _pendingImageBase64;

  late final AIBookingAgent _agent;
  final _locationService = LocationService();
  final _scanner = ReceiptScannerService();

  @override
  void initState() {
    super.initState();
    _agent = AIBookingAgent();
    _messages.add(ChatMessage(text: AppStrings.greeting(AppLocale.tradChinese), isUser: false));
  }

  void _refreshGreeting() {
    final locale = ref.read(localeProvider);
    setState(() {
      _messages.clear();
      _messages.add(ChatMessage(text: AppStrings.greeting(locale), isUser: false));
    });
  }

  // ─────────────────────────────────────────────
  // Image attachment
  // ─────────────────────────────────────────────
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );
    if (image == null) return;

    final bytes = await image.readAsBytes();
    final base64 = base64Encode(bytes);

    setState(() {
      _attachedImage = image;
      _attachedImageBase64 = base64;
      _isExtractingLocation = true;
    });
    await _extractExifLocation(image);
    if (mounted) setState(() => _isExtractingLocation = false);
  }

  Future<void> _takePhoto() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );
    if (image == null) return;

    final bytes = await image.readAsBytes();
    final base64 = base64Encode(bytes);

    setState(() {
      _attachedImage = image;
      _attachedImageBase64 = base64;
      _isExtractingLocation = true;
    });
    await _extractExifLocation(image);
    if (mounted) setState(() => _isExtractingLocation = false);
  }

  Future<void> _extractExifLocation(XFile image) async {
    try {
      final file = File(image.path);
      final gps = await _scanner.extractGpsFromFile(file);

      if (gps != null) {
        final locResult = _locationService.reverseGeocode(gps);
        if (locResult != null && (locResult.confidence ?? 0) > 0.5) {
          final confirmed = await _showLocationConfirmationDialog(context, locResult.displayText);
          if (confirmed != null) {
            setState(() => _extractedLocation = confirmed);
            return;
          }
        }
      }

      await _loadDefaultLocation();
    } catch (e) {
      await _loadDefaultLocation();
    }
  }

  Future<String?> _showLocationConfirmationDialog(BuildContext context, String detectedLocation) async {
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('📍 確認地點'),
        content: Text('系統偵測到您可能喺「$detectedLocation」'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, detectedLocation),
            child: const Text('✅ 是'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('❌ 不是'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('📍 手動選擇'),
          ),
        ],
      ),
    );
  }

  double _parseGpsCoordinate(IfdTag tag, IfdTag ref) {
    final values = tag.values;
    if (values is IfdRatios && values.ratios.length >= 3) {
      final ratio = values.ratios;
      final degrees = ratio[0].toDouble();
      final minutes = ratio[1].toDouble();
      final seconds = ratio[2].toDouble();

      var result = degrees + (minutes / 60.0) + (seconds / 3600.0);

      final refStr = ref.toString().toUpperCase();
      if (refStr == 'S' || refStr == 'W') result = -result;

      return result;
    }
    return 0.0;
  }

  Future<void> _loadDefaultLocation() async {
    try {
      final client = supabase;
      final userId = client.auth.currentSession?.user.id;
      if (userId == null) return;

      final profile = await client
          .from('user_profiles')
          .select('default_location')
          .eq('id', userId)
          .maybeSingle();

      if (profile != null && profile['default_location'] != null) {
        setState(() => _extractedLocation = profile['default_location']);
      }
    } catch (e) {
      // ignore
    }
  }

  Future<String?> _showLocationPickerDialog(BuildContext context) async {
    final districts = ['九龍', '新界', '港島', '旺角', '灣仔', '北角', '粉嶺', '大埔', '其他'];

    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('📍 添加位置'),
        content: SizedBox(
          width: double.maxFinite,
          child: GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            children: districts.map((d) => ListTile(
              title: Text(d),
              onTap: () => Navigator.pop(ctx, d),
            )).toList(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        ],
      ),
    );
  }

  Future<String?> _reverseGeocode(double lat, double lon) async {
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?lat=$lat&lon=$lon&format=json&accept-language=zh-tw',
      );
      final httpClient = HttpClient();
      final req = await httpClient.getUrl(uri);
      final resp = await req.close();
      final jsonStr = await resp
          .transform(utf8.decoder)
          .join();

      final districtMatch = RegExp(r'"city"\s*:\s*"([^"]*)"').firstMatch(jsonStr);
      final areaMatch = RegExp(r'"state"\s*:\s*"([^"]*)"').firstMatch(jsonStr);
      final suburbMatch = RegExp(r'"suburb"\s*:\s*"([^"]*)"').firstMatch(jsonStr);

      final location = districtMatch?.group(1) ?? areaMatch?.group(1) ?? suburbMatch?.group(1);
      return location;
    } catch (e) {
      return null;
    }
  }

  void _removeAttachment() {
    setState(() {
      _attachedImage = null;
      _attachedImageBase64 = null;
      _extractedLocation = null;
    });
  }

  // ─────────────────────────────────────────────
  // Send message
  // ─────────────────────────────────────────────
  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty && _attachedImage == null) return;

    final locale = ref.read(localeProvider);

    setState(() {
      _messages.add(ChatMessage(
        text: text.isEmpty ? AppStrings.photoExpense(locale) : text,
        isUser: true,
        imagePath: _attachedImageBase64, // use base64 for reliable display
      ));
      _isTyping = true;
    });

    _messageController.clear();
    // Save to pending buffers so dialog can access after _sendMessage returns
    _pendingImage = _attachedImage;
    _pendingImageBase64 = _attachedImageBase64;
    _pendingLocation = _extractedLocation;
    // Wait for location extraction to finish before sending
    while (_isExtractingLocation) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    _scrollToBottom();

    try {
      debugPrint('🔵 [_sendMessage] Sending message: $text');
      final userId = supabase.auth.currentUser?.id;
      debugPrint('🔵 [_sendMessage] userId: $userId');
      final intent = await _agent.parseExpense(
        text.isEmpty ? 'photo expense' : text,
        userId: userId,
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('AI timeout'),
      );
      debugPrint('🔵 [_sendMessage] Received intent: intent=${intent.intent}, confidence=${intent.confidence}, amount=${intent.amount}, items=${intent.items}');

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

      if (intent.confidence > 0.7 && (intent.amount != null || intent.items.isNotEmpty)) {
        _showSaveDialog(intent, _pendingImage, _pendingLocation, _pendingImageBase64);
      }
    } catch (e) {
      final locale = ref.read(localeProvider);
      String errorMsg;
      if (e.toString().contains('timeout')) {
        errorMsg = AppStrings.timeout(locale);
      } else if (e.toString().contains('rate_limit') || e.toString().contains('rate_limited')) {
        errorMsg = AppStrings.rateLimited(locale);
      } else {
        errorMsg = '${AppStrings.sorryError(locale)}\n錯誤：${e.toString().substring(0, 100)}';
        debugPrint('Chat error: $e');
      }
      setState(() {
        _messages.add(ChatMessage(text: errorMsg, isUser: false));
        _isTyping = false;
      });
    }

    setState(() {
      _attachedImage = null;
      _attachedImageBase64 = null;
      _extractedLocation = null;
      _pendingImage = null;
      _pendingLocation = null;
      _pendingImageBase64 = null;
    });
  }

  void _showSaveDialog(ExpenseIntent intent, XFile? image, String? location, String? imageBase64) {
    final locale = ref.read(localeProvider);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppStrings.confirmExpense(locale)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imageBase64 != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  base64Decode(imageBase64),
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text('${AppStrings.input(locale)}：${intent.rawText}'),
            const SizedBox(height: 4),
            Text('${AppStrings.category(locale)}：${intent.category ?? "未知"}'),
            if (intent.amount != null)
              Text('${AppStrings.amount(locale)}：\$${intent.amount!.toStringAsFixed(0)}'),
            Text('${AppStrings.confidence(locale)}：${(intent.confidence * 100).toInt()}%'),
            if (intent.items.isNotEmpty)
              Text('${AppStrings.items(locale)}：${intent.items.join("、")}'),
            if (location != null) Text('${AppStrings.location(locale)}：$location'),
            if (image != null) Text(AppStrings.photoAttached(locale)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppStrings.cancel(locale)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _saveExpense(intent, image, location, imageBase64: imageBase64);
            },
            child: Text(AppStrings.confirm(locale)),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // Save expense
  // ─────────────────────────────────────────────
  Future<void> _saveExpense(ExpenseIntent intent, XFile? image, String? location, {String? imageBase64}) async {
    final locale = ref.read(localeProvider);
    try {
      final client = supabase;
      final now = DateTime.now().millisecondsSinceEpoch;
      final userId = client.auth.currentSession?.user.id;
      if (userId == null) throw Exception('Not logged in');
      final relations = await client
          .from('employer_helper_relations')
          .select('employer_id, id')
          .eq('helper_id', userId)
          .eq('status', 'active')
          .maybeSingle();

      final employerId = relations?['employer_id'];
      final relationId = relations?['id'];

      String? imageStorageUrl;
      if (image != null) {
        imageStorageUrl = await _uploadImage(image, userId, base64: imageBase64);
      }

      final items = _buildItemsFromIntent(intent);
      final transactionDate = _parseTransactionDate(intent.rawText) ?? DateTime.now();

      final receiptId = Uuid().v4();

      String? matchedShopId;
      final storeName = intent.storeName ?? _extractShopNameFromRawText(intent.rawText);
      if (storeName != null && storeName.isNotEmpty) {
        final shopService = ShopMatchingService(supabase);
        final shopResult = await shopService.matchShop(
          rawShopName: storeName,
          shopType: intent.category,
        );
        matchedShopId = shopResult?.shopId;
      }

      String? _extractShopNameFromRawText(String rawText) {
        // Try to extract shop-like keywords from rawText
        final patterns = [
          RegExp(r'(街市|市場|market)', CaseInsensitive: true),
          RegExp(r'(惠康|百佳|萬寧|屈臣氏|超市)', CaseInsensitive: true),
          RegExp(r'(菜市場|魚市場|肉檔)', CaseInsensitive: true),
          RegExp(r'(wet market|supermarket)', CaseInsensitive: true),
        ];
        for (final pattern in patterns) {
          final match = pattern.firstMatch(rawText);
          if (match != null) return match.group(0)!;
        }
        return null;
      }

      await client.from('receipts').insert({
        'id': receiptId,
        'employer_id': employerId,
        'helper_id': userId,
        'relation_id': relationId,
        'raw_text': intent.rawText,
        'parsed_data': {
          'intent': intent.intent,
          'store_cate': intent.category,
          'amount': intent.amount,
          'items': intent.items,
          'store_name': intent.storeName,
        },
        'amount': intent.amount,
        'store_cate': intent.category,
        'location': location,
        'transaction_date': transactionDate?.toIso8601String().split('T')[0],
        'image_local_path': imageStorageUrl,
        'shop_id': matchedShopId,
        'sync_status': 'synced',
        'local_timestamp': now,
        'created_at': DateTime.now().toIso8601String(),
      });

      if (items.isNotEmpty) {
        await client.from('receipt_items').insert(
          items.map((item) => {
            'receipt_id': receiptId,
            'item_name': item['item_name'],
            'item_raw_text': item['item_raw_text'],
            'qty': item['qty'],
            'unit_price': item['unit_price'],
            'actual_price': item['actual_price'],
            'is_discounted': item['is_discounted'],
            'discount_note': item['discount_note'],
            'prd_cate': item['prd_cate'],
            'line_total': item['line_total'],
            'created_at': DateTime.now().toIso8601String(),
          }).toList(),
        );

        // Phase 4: Match products and write price_history
        await _matchProductsAndWritePriceHistory(receiptId, items, matchedShopId, location);
      } else {
        await client.from('receipt_items').insert({
          'receipt_id': receiptId,
          'item_name': intent.items.isNotEmpty ? intent.items.first : intent.rawText,
          'item_raw_text': intent.rawText,
          'qty': 1,
          'unit_price': intent.amount,
          'actual_price': intent.amount,
          'is_discounted': false,
          'discount_note': null,
          'prd_cate': _mapToPrdCate(intent.category, intent.items.isNotEmpty ? intent.items.first : intent.rawText),
          'line_total': intent.amount,
          'created_at': DateTime.now().toIso8601String(),
        });
      }

      await _matchProductsAndWritePriceHistory(receiptId, singleItem, matchedShopId, location);

      if (employerId != null) {
        try {
          await client.functions.invoke('notification-broadcast', body: {
            'type': 'INSERT',
            'table': 'receipts',
            'record': {
              'id': receiptId,
              'employer_id': employerId,
              'helper_id': userId,
              'relation_id': relationId,
              'store_name': null,
              'amount': intent.amount,
              'created_at': DateTime.now().toIso8601String(),
            },
          });
        } catch (e) {
          debugPrint('Notification broadcast failed: $e');
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.expenseSaved(locale)),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppStrings.expenseSaveFailed(locale)}：$e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<String?> _uploadImage(XFile image, String userId, {String? base64}) async {
    try {
      final client = supabase;
      final fileName = '${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final bytes = base64 != null
          ? base64Decode(base64)
          : await image.readAsBytes();

      debugPrint('_uploadImage: attempting storage upload, file=$fileName, size=${bytes.length}');

      try {
        final storage = client.storage.from('receipts');
        final filePath = 'receipts/$fileName';
        
        await storage.uploadBinary(
          filePath, 
          bytes,
        );

        // Use getPublicUrl like scan_screen does (bucket is public)
        final publicUrl = storage.getPublicUrl(filePath);
        debugPrint('_uploadImage: success, publicUrl=$publicUrl');
        return publicUrl;
      } catch (storageError) {
        debugPrint('_uploadImage: storage failed, falling back to base64, error=$storageError');
        return base64;
      }
    } catch (e) {
      debugPrint('_uploadImage: error=$e');
      return null;
    }
  }

  List<Map<String, dynamic>> _buildItemsFromIntent(ExpenseIntent intent) {
    if (intent.items.isEmpty) return [];

    return List.generate(intent.items.length, (i) {
      final itemName = intent.items[i];
      final itemRawText = i < intent.itemRawTexts.length && intent.itemRawTexts[i].isNotEmpty
          ? intent.itemRawTexts[i]
          : intent.rawText;
      final price = _extractPriceForItem(intent.rawText, itemName) ?? intent.amount;
      final prdCate = _mapToPrdCate(intent.category, itemName);

      return {
        'item_name': itemName,         // LLM-translated Chinese name
        'item_raw_text': itemRawText,  // original raw input for audit
        'qty': 1,
        'unit_price': price,
        'actual_price': price,
        'prd_cate': prdCate,
        'line_total': price,
      };
    });
  }

  double? _extractPriceForItem(String rawText, String itemName) {
    // Pattern 1: Item name or generic patterns followed by price
    // e.g. "魚 40$", "40$ jin", "fish 40 dollars", "40 dollars"
    final pricePatterns = [
      r'(\d+(?:\.\d{1,2})?)\s*\$',           // "40$" or "40.5$"
      r'\$\s*(\d+(?:\.\d{1,2})?)',           // "$40"
      r'(\d+(?:\.\d{1,2})?)\s*(?:蚊|元|塊| dollars?)',  // "40蚊", "40元"
      r'(\d+(?:\.\d{1,2})?)\s*[Jj]in',       // "40 jin" (斤)
    ];

    for (final patternStr in pricePatterns) {
      final regex = RegExp(patternStr, caseSensitive: false);
      final match = regex.firstMatch(rawText);
      if (match != null) {
        final result = double.tryParse(match.group(1)!);
        if (result != null && result > 0) return result;
      }
    }

    return null;
  }

  String _mapToPrdCate(String? storeCate, String itemName) {
    // First try to infer from item name keywords (multi-language)
    final lowerItem = itemName.toLowerCase();
    if (_containsAny(lowerItem, ['魚', 'snapper', 'pulang', 'isda', 'ikan', 'fish', 'bangus', '魽', '石斑', '紅衫'])) return 'fish';
    if (_containsAny(lowerItem, ['豬', 'pork', 'carne', 'baboy', 'daging babi'])) return 'pork';
    if (_containsAny(lowerItem, ['牛', 'beef', 'carne de res', 'sapi'])) return 'beef';
    if (_containsAny(lowerItem, ['雞', 'chicken', 'manok', 'ayam'])) return 'chicken';
    if (_containsAny(lowerItem, ['菜', '蔬菜', 'vegetables', 'gulay', 'sayur'])) return 'vegetables';
    if (_containsAny(lowerItem, ['米', '飯', 'rice', 'kanin', 'nasi'])) return 'rice';
    if (_containsAny(lowerItem, ['油', 'oil'])) return 'oil';
    if (_containsAny(lowerItem, ['調味料', 'seasoning', '鹽', '糖'])) return 'seasoning';
    if (_containsAny(lowerItem, ['零食', 'snack', '餅', '糖果'])) return 'snack';
    if (_containsAny(lowerItem, ['飲', 'drink', '水', 'coffee', '茶', 'milk'])) return 'drink';
    if (_containsAny(lowerItem, ['日用', 'daily', '紙巾', '牙膏'])) return 'daily';
    if (_containsAny(lowerItem, ['外賣', 'takeaway', 'take out'])) return 'takeaway';

    // Fallback to store_cate mapping
    switch (storeCate) {
      case 'wet_market': return 'other';
      case 'supermarket': return 'other';
      case 'pharmacy': return 'other';
      case 'convenience': return 'other';
      case 'restaurant':
      case 'cafe': return 'other';
      case 'takeaway': return 'takeaway';
      default: return 'other';
    }
  }

  bool _containsAny(String text, List<String> keywords) {
    return keywords.any((kw) => text.contains(kw));
  }

  DateTime? _parseTransactionDate(String rawText) {
    if (rawText.isEmpty) return null;

    final match1 = RegExp(r'(\d{1,2})[/\-](\d{1,2})[/\-](\d{4})').firstMatch(rawText);
    if (match1 != null) {
      final d = int.parse(match1.group(1)!);
      final m = int.parse(match1.group(2)!);
      final y = int.parse(match1.group(3)!);
      if (y > 1900 && y < 2100 && m >= 1 && m <= 12 && d >= 1 && d <= 31) {
        return DateTime(y, m, d);
      }
    }
    final match2 = RegExp(r'(\d{4})[/\-](\d{1,2})[/\-](\d{1,2})').firstMatch(rawText);
    if (match2 != null) {
      final y = int.parse(match2.group(1)!);
      final m = int.parse(match2.group(2)!);
      final d = int.parse(match2.group(3)!);
      if (y > 1900 && y < 2100 && m >= 1 && m <= 12 && d >= 1 && d <= 31) {
        return DateTime(y, m, d);
      }
    }
    return null; // caller will use DateTime.now()
  }

  Future<void> _matchProductsAndWritePriceHistory(
    String receiptId,
    List<Map<String, dynamic>> items,
    String? shopId,
    String? location,
  ) async {
    if (items.isEmpty) return;

    try {
      final client = supabase;
      final productService = ProductMatchingService(client);

      // For each item, match to master_product + write price_history
      for (final item in items) {
        final itemName = item['item_name'] as String? ?? '';
        final rawText = item['item_raw_text'] as String? ?? itemName;
        final unitPrice = (item['unit_price'] as num?)?.toDouble();
        final actualPrice = (item['actual_price'] as num?)?.toDouble();
        final prdCate = item['prd_cate'] as String? ?? 'other';

        if (unitPrice == null && actualPrice == null) continue;

        // Match product (creates master_product + alias if not exists)
        final result = await productService.matchProduct(
          rawName: rawText,
          defaultUnit: '斤',
          prdCate: prdCate,
        );

        final priceToRecord = actualPrice ?? unitPrice!;

        // Write price_history
        await client.from('price_history').insert({
          'master_product_id': result.masterProductId,
          'shop_id': shopId,
          'location': location,
          'price': priceToRecord,
          'original_price': unitPrice,
          'total_paid': actualPrice,
          'is_discount_bundle': item['is_discounted'] == true,
          'unit': '斤',
          'source_receipt_id': receiptId,
          'recorded_at': DateTime.now().toIso8601String().split('T')[0],
        });
      }
    } catch (e) {
      debugPrint('_matchProductsAndWritePriceHistory error: $e');
    }
  }

  void _showNeedRelationDialog() {
    final locale = ref.read(localeProvider);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppStrings.needLinkEmployer(locale)),
        content: Text(AppStrings.enterInviteCode(locale)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppStrings.ok(locale)),
          ),
        ],
      ),
    );
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
    final locale = ref.watch(localeProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.get(locale, 'chat')),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshGreeting,
          ),
        ],
      ),
      body: Column(
        children: [
          // Attachment preview bar
          if (_attachedImage != null || _extractedLocation != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  if (_attachedImage != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        base64Decode(_attachedImageBase64!),
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(AppStrings.photoAttached(locale)),
                    const SizedBox(width: 8),
                  ],
                  if (_extractedLocation != null) ...[
                    const Icon(Icons.location_on, size: 16),
                    Text(_extractedLocation!),
                  ],
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: _removeAttachment,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

          // Messages
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

          // Typing indicator
          if (_isTyping)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  const Text('🤖 ', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(AppStrings.aiThinking(locale)),
                ],
              ),
            ),

          // Input area
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Attachments row (icons)
                  Row(
                    children: [
                      IconButton(
                        onPressed: _takePhoto,
                        icon: const Icon(Icons.camera_alt),
                        tooltip: AppStrings.takePhoto(locale),
                      ),
                      IconButton(
                        onPressed: _pickImage,
                        icon: const Icon(Icons.photo_library),
                        tooltip: AppStrings.pickPhoto(locale),
                      ),
                      IconButton(
                        icon: const Icon(Icons.location_on_outlined, color: Colors.grey),
                        onPressed: () async {
                          final result = await _showLocationPickerDialog(context);
                          if (result != null) {
                            setState(() => _extractedLocation = result);
                          }
                        },
                        tooltip: '📍 添加位置（可選）',
                      ),
                      const Spacer(),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (_extractedLocation != null)
                        Chip(
                          label: Text(_extractedLocation!, style: const TextStyle(fontSize: 12)),
                          deleteIcon: const Icon(Icons.close, size: 14),
                          onDeleted: () => setState(() => _extractedLocation = null),
                        ),
                      if (_extractedLocation != null) const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          decoration: InputDecoration(
                            hintText: AppStrings.typeExpenseHint(locale),
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
  final String? imagePath;

  const ChatMessage({
    required this.text,
    required this.isUser,
    this.data,
    this.imagePath,
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.imagePath != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: message.imagePath!.length > 100
                      ? Image.memory(
                          base64Decode(message.imagePath!),
                          width: 120,
                          height: 120,
                          fit: BoxFit.cover,
                        )
                      : Image.file(
                          File(message.imagePath!),
                          width: 120,
                          height: 120,
                          fit: BoxFit.cover,
                        ),
                ),
              ),
            Text(
              message.text,
              style: TextStyle(
                color: message.isUser ? Colors.white : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}