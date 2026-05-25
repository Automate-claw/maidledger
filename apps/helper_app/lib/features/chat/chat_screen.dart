import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:exif/exif.dart';
import 'package:maidledger_localization/maidledger_localization.dart';
import '../../core/services/supabase_client_provider.dart';
import '../../core/services/ai_booking_agent_service.dart';
import '../../core/services/shop_matching_service.dart';
import '../../core/services/product_matching_service.dart';
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
  AppLocale get _locale => ref.watch(localeProvider);
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isTyping = false;
  bool _greetingSet = false;
  String _previousLocaleCode = '';

  // Attached image state
  XFile? _attachedImage;
  String? _extractedLocation;
  bool _isExtractingLocation = false; // blocks send until location is ready
  String? _attachedImageBase64; // for reliable display

  // Buffer for save dialog (needed because dialog outlives _sendMessage scope)
  XFile? _pendingImage;
  String? _pendingLocation;
  String? _pendingImageBase64;
  bool _imageUsedFallback = false;

  late final AIBookingAgent _agent;
  final _locationService = LocationService();
  final _scanner = ReceiptScannerService();

  @override
  void initState() {
    super.initState();
    _agent = AIBookingAgent();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final currentLocaleCode = ref.read(localeProvider).code;
    // Refresh greeting when locale changes (not just first mount)
    if (!_greetingSet || currentLocaleCode != _previousLocaleCode) {
      _previousLocaleCode = currentLocaleCode;
      _greetingSet = true;
      _messages.clear();
      _messages.add(ChatMessage(text: AppStrings.greeting(ref.read(localeProvider)), isUser: false));
    }
  }

  void _refreshGreeting() {
    final locale = ref.read(localeProvider);
    setState(() {
      _messages.clear();
      _messages.add(ChatMessage(text: AppStrings.greeting(_locale), isUser: false));
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
        title: Text('📍 ${AppStrings.confirmLocation(_locale)}'),
        content: Text('${AppStrings.confirmLocation(_locale)} 「$detectedLocation」'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, detectedLocation),
            child: Text(AppStrings.confirm(_locale)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: Text(AppStrings.cancel(_locale)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final result = await _showLocationPickerDialog(context);
              if (result != null) {
                Navigator.pop(context, result);
              }
            },
            child: Text(AppStrings.location(_locale)),
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
        title: Text('📍 ${AppStrings.location(_locale)}'),
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppStrings.cancel(_locale))),
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

  Future<bool> _checkConnectivity() async {
    final locale = ref.read(localeProvider);
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.noNetwork(_locale)),
            backgroundColor: Colors.orange,
          ),
        );
      }
      setState(() => _isTyping = false);
      return false;
    }
    return true;
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
        text: text.isEmpty ? AppStrings.photoExpense(_locale) : text,
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
      if (!await _checkConnectivity()) return;
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
      if (e is TimeoutException) {
        errorMsg = AppStrings.timeout(_locale);
      } else if (e.toString().contains('timeout') && e.toString().contains('AI timeout')) {
        errorMsg = AppStrings.timeout(_locale);
      } else if (e.toString().contains('rate_limit') || e.toString().contains('rate_limited')) {
        errorMsg = AppStrings.rateLimited(_locale);
      } else {
        errorMsg = '${AppStrings.sorryError(_locale)}\n錯誤：${e.toString().substring(0, 100)}';
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
        title: Text(AppStrings.confirmExpense(_locale)),
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
            Text('${AppStrings.input(_locale)}：${intent.rawText}'),
            const SizedBox(height: 4),
            Text('${AppStrings.category(_locale)}：${intent.category ?? "未知"}'),
            if (intent.amount != null)
              Text('${AppStrings.amount(_locale)}：\$${intent.amount!.toStringAsFixed(0)}'),
            Text('${AppStrings.confidence(_locale)}：${(intent.confidence * 100).toInt()}%'),
            if (intent.items.isNotEmpty)
              Text('${AppStrings.items(_locale)}：${intent.items.join("、")}'),
            if (location != null) Text('${AppStrings.location(_locale)}：$location'),
            if (image != null) Text(AppStrings.photoAttached(_locale)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppStrings.cancel(_locale)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _saveExpense(intent, image, location, imageBase64: imageBase64);
            },
            child: Text(AppStrings.confirm(_locale)),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // Save expense — all business logic in chat-orchestrate Edge Function
  // ─────────────────────────────────────────────
  Future<void> _saveExpense(ExpenseIntent intent, XFile? image, String? location, {String? imageBase64}) async {
    final locale = ref.read(localeProvider);
    try {
      final client = supabase;
      final userId = client.auth.currentSession?.user.id;
      if (userId == null) throw Exception('Not logged in');

      // Upload image if provided (audit trail only — primary upload is in chat-orchestrate via receipt-writer)
      if (image != null) {
        await _uploadImage(image, userId, base64: imageBase64);
      }

      // All business logic now in chat-orchestrate:
      // - receipt-writer createFromChat (employer lookup + receipt insert)
      // - shop-manager upsert + receipt-writer writeShopLink (if store name)
      // - receipt-writer writeItemsFromChat
      // - product-manager upsert loop + price_history writes
      final aiAgent = AIBookingAgent();
      final result = await aiAgent.saveExpense(intent.rawText, userId, location: location, imageBase64: imageBase64);

      if (result['success'] != true) {
        final errors = (result['errors'] as List?)?.join('; ') ?? AppStrings.expenseSaveFailed(_locale);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(errors), backgroundColor: Colors.red),
          );
        }
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.expenseSaved(_locale)),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('_saveExpense error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppStrings.expenseSaveFailed(_locale)}：$e'),
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
        _imageUsedFallback = false;
        return publicUrl;
      } catch (storageError) {
        debugPrint('_uploadImage: storage failed, falling back to base64, error=$storageError');
        _imageUsedFallback = true;
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

    double? maxPrice;
    for (final patternStr in pricePatterns) {
      final regex = RegExp(patternStr, caseSensitive: false);
      final matches = regex.allMatches(rawText);
      for (final match in matches) {
        final result = double.tryParse(match.group(1)!);
        if (result != null && result > 0) {
          if (maxPrice == null || result > maxPrice) {
            maxPrice = result;
          }
        }
      }
    }

    return maxPrice;
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
        // Use LLM-translated item_name for matching (not rawText which has price/unit)
        // rawText preserved in item_raw_text for audit
        final itemName = item['item_name'] as String? ?? '';
        final rawText = item['item_raw_text'] as String? ?? itemName;
        final unitPrice = (item['unit_price'] as num?)?.toDouble();
        final actualPrice = (item['actual_price'] as num?)?.toDouble();
        final prdCate = item['prd_cate'] as String? ?? 'other';

        if (unitPrice == null && actualPrice == null) continue;

        // Match product (creates master_product + alias if not exists)
        var result = await productService.matchItem(
          itemName: itemName,  // use translated name for better matching
          prdCate: prdCate,
        );

        // If no match, create new master product using translated name
        if (result == null) {
          try {
            result = await productService.createMasterProduct(
              rawName: itemName,  // canonical = translated name
              prdCate: prdCate,
              defaultUnit: '斤',
            );
            // Also create alias from original raw text
            if (rawText != itemName) {
              await client.from('product_aliases').upsert({
                'raw_name': rawText.trim(),
                'master_product_id': result.masterProductId,
                'source': 'chat',
              });
            }
          } catch (e) {
            debugPrint('createMasterProduct error: $e');
            continue;
          }
        }

        // Attach master_product_id to item for use by Phase 6
        item['master_product_id'] = result.masterProductId;

        // Also bind receipt_items.master_product_id
        await client.from('receipt_items')
            .update({'master_product_id': result.masterProductId})
            .eq('receipt_id', receiptId)
            .eq('item_name', itemName);

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

  Future<void> _upsertExpenseSummary(
    String? employerId,
    String? helperId,
    String? relationId,
    DateTime transactionDate,
    List<Map<String, dynamic>> items,
  ) async {
    if (employerId == null || items.isEmpty) return;

    try {
      final client = supabase;
      final month = DateTime(transactionDate.year, transactionDate.month, 1);

      for (final item in items) {
        final prdCate = item['prd_cate'] as String? ?? 'other';
        final amount = (item['line_total'] as num?)?.toDouble() ?? 0;
        if (amount <= 0) continue;

        // Find existing summary record
        final existing = await client
            .from('expense_summaries')
            .select('id, total_amount, transaction_count')
            .eq('employer_id', employerId)
            .eq('month', month.toIso8601String().split('T')[0])
            .eq('category', prdCate)
            .maybeSingle();

        if (existing != null) {
          // Update existing record
          await client.from('expense_summaries').update({
            'total_amount': (existing['total_amount'] as num? ?? 0) + amount,
            'transaction_count': (existing['transaction_count'] as int? ?? 0) + 1,
          }).eq('id', existing['id']);
        } else {
          // Insert new record
          await client.from('expense_summaries').insert({
            'employer_id': employerId,
            'helper_id': helperId,
            'relation_id': relationId,
            'month': month.toIso8601String().split('T')[0],
            'category': prdCate,
            'total_amount': amount,
            'transaction_count': 1,
          });
        }
      }
    } catch (e) {
      debugPrint('_upsertExpenseSummary error: $e');
    }
  }

  Future<void> _triggerPriceAlerts(
    String receiptId,
    List<Map<String, dynamic>> items,
  ) async {
    try {
      final client = supabase;
      for (final item in items) {
        final masterProductId = item['master_product_id'] as String?;
        final unitPrice = (item['unit_price'] as num?)?.toDouble();
        if (masterProductId == null || unitPrice == null) continue;

        await client.functions.invoke('price-alert-engine', body: {
          'type': 'new_price',
          'receipt_id': receiptId,
          'master_product_id': masterProductId,
          'new_price': unitPrice,
          'unit': '斤',
        });
      }
    } catch (e) {
      debugPrint('_triggerPriceAlerts error: $e');
    }
  }

  void _showNeedRelationDialog() {
    final locale = ref.read(localeProvider);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppStrings.needLinkEmployer(_locale)),
        content: Text(AppStrings.enterInviteCode(_locale)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppStrings.ok(_locale)),
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
                    Text(AppStrings.photoAttached(_locale)),
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
                  Text(AppStrings.aiThinking(_locale)),
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
                        tooltip: AppStrings.takePhoto(_locale),
                      ),
                      IconButton(
                        onPressed: _pickImage,
                        icon: const Icon(Icons.photo_library),
                        tooltip: AppStrings.pickPhoto(_locale),
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
                            hintText: AppStrings.typeExpenseHint(_locale),
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