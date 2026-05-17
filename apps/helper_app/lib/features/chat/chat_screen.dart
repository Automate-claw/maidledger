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

  late final AIBookingAgent _agent;

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

    setState(() => _attachedImage = image);
    await _extractExifLocation(image);
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

    setState(() => _attachedImage = image);
    await _extractExifLocation(image);
  }

  Future<void> _extractExifLocation(XFile image) async {
    try {
      final bytes = await image.readAsBytes();
      final tags = await readExifFromBytes(bytes);

      final lat = tags['GPS GPSLatitude'];
      final latRef = tags['GPS GPSLatitudeRef'];
      final lon = tags['GPS GPSLongitude'];
      final lonRef = tags['GPS GPSLongitudeRef'];

      if (lat == null || lon == null || latRef == null || lonRef == null) {
        await _loadDefaultLocation();
        return;
      }

      final latitude = _parseGpsCoordinate(lat, latRef);
      final longitude = _parseGpsCoordinate(lon, lonRef);

      final locationName = await _reverseGeocode(latitude, longitude);
      setState(() => _extractedLocation = locationName);
    } catch (e) {
      await _loadDefaultLocation();
    }
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
        imagePath: _attachedImage?.path,
      ));
      _isTyping = true;
    });

    _messageController.clear();
    final imageForSend = _attachedImage;
    final locationForSend = _extractedLocation;
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
        _showSaveDialog(intent, imageForSend, locationForSend);
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
      _extractedLocation = null;
    });
  }

  void _showSaveDialog(ExpenseIntent intent, XFile? image, String? location) {
    final locale = ref.read(localeProvider);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppStrings.confirmExpense(locale)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
              _saveExpense(intent, image, location);
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
  Future<void> _saveExpense(ExpenseIntent intent, XFile? image, String? location) async {
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
        imageStorageUrl = await _uploadImage(image, userId);
      }

      final items = _buildItemsFromIntent(intent);
      final transactionDate = _parseTransactionDate(intent.rawText);

      final receiptId = Uuid().v4();
      await client.from('receipts').insert({
        'id': receiptId,
        'employer_id': employerId,
        'helper_id': userId,
        'relation_id': relationId,
        'raw_text': intent.rawText,
        'parsed_data': {
          'intent': intent.intent,
          'category': intent.category,
          'amount': intent.amount,
          'items': intent.items,
        },
        'amount': intent.amount,
        'category': intent.category,
        'location': location,
        'transaction_date': transactionDate?.toIso8601String().split('T')[0],
        'image_local_path': imageStorageUrl,
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
            'prd_cate': item['prd_cate'],
            'line_total': item['line_total'],
            'created_at': DateTime.now().toIso8601String(),
          }).toList(),
        );
      } else {
        await client.from('receipt_items').insert({
          'receipt_id': receiptId,
          'item_name': intent.items.isNotEmpty ? intent.items.first : intent.rawText,
          'item_raw_text': intent.rawText,
          'qty': 1,
          'unit_price': intent.amount,
          'prd_cate': intent.category ?? 'other',
          'line_total': intent.amount,
          'created_at': DateTime.now().toIso8601String(),
        });
      }

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

  Future<String?> _uploadImage(XFile image, String userId) async {
    try {
      final client = supabase;
      final fileName = '${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final bytes = await image.readAsBytes();

      await client.storage
          .from('receipts')
          .uploadBinary(fileName, bytes);

      final url = client.storage
          .from('receipts')
          .getPublicUrl(fileName);

      return url;
    } catch (e) {
      return null;
    }
  }

  List<Map<String, dynamic>> _buildItemsFromIntent(ExpenseIntent intent) {
    if (intent.items.isEmpty) return [];

    return intent.items.map((itemName) {
      final price = _extractPriceForItem(intent.rawText, itemName);
      final category = _mapToPrdCate(intent.category);

      return {
        'item_name': itemName,
        'item_raw_text': itemName,
        'qty': 1,
        'unit_price': price,
        'prd_cate': category,
        'line_total': price,
      };
    }).toList();
  }

  double? _extractPriceForItem(String rawText, String itemName) {
    final pattern1 = RegExp(itemName + r'\s*[美澳散]?\s*\$?\s*(\d+(?:\.\d{1,2})?)');
    final pattern2 = RegExp(r'(\d+(?:\.\d{1,2})?)\s*[蚊元塊]');

    final match1 = pattern1.firstMatch(rawText);
    if (match1 != null) return double.tryParse(match1.group(1)!);

    final match2 = pattern2.firstMatch(rawText);
    if (match2 != null) return double.tryParse(match2.group(1)!);

    return null;
  }

  String _mapToPrdCate(String? category) {
    switch (category) {
      case 'food':
      case 'market':
      case 'supermarket':
        return 'other';
      default:
        return 'other';
    }
  }

  DateTime? _parseTransactionDate(String rawText) {
    final match1 = RegExp(r'(\d{1,2})[/\-](\d{1,2})[/\-](\d{4})').firstMatch(rawText);
    if (match1 != null) {
      final g1 = int.parse(match1.group(1)!);
      final g2 = int.parse(match1.group(2)!);
      final g3 = int.parse(match1.group(3)!);
      return DateTime(g3, g2, g1);
    }
    final match2 = RegExp(r'(\d{4})[/\-](\d{1,2})[/\-](\d{1,2})').firstMatch(rawText);
    if (match2 != null) {
      final g1 = int.parse(match2.group(1)!);
      final g2 = int.parse(match2.group(2)!);
      final g3 = int.parse(match2.group(3)!);
      return DateTime(g1, g2, g3);
    }
    return null;
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
                      child: Image.file(
                        File(_attachedImage!.path),
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
                      const Spacer(),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
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
                  child: Image.file(
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