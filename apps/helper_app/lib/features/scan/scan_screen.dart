import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import '../../core/services/supabase_client_provider.dart';
import '../../core/services/receipt_scanner_provider.dart';
import '../../core/services/receipt_scanner_service.dart';

/// Camera scan screen for receipt scanning
/// Workflow: Photo → Compress → Upload to Storage → OCR → Edge LLM Parse → DB
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isProcessing = false;
  String? _lastScannedText;
  String? _lastImageUrl;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        _showError('No cameras available');
        return;
      }

      final backCamera = _cameras!.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _cameraController!.initialize();

      if (mounted) {
        setState(() => _isInitialized = true);
      }
    } catch (e) {
      _showError('Camera initialization failed: $e');
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  void _showSnackbar(String message, {bool isLoading = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: isLoading
            ? Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(message),
                ],
              )
            : Text(message),
        duration: Duration(seconds: isLoading ? 10 : 3),
      ),
    );
  }

  // ============================================================
  // Core workflow: Photo → Compress → Upload → OCR → Edge LLM → DB
  // ============================================================

  Future<void> _captureAndScan() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    if (_isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      // Step 1: Capture photo
      final XFile image = await _cameraController!.takePicture();

      // Step 2: Compress image (target: ~500KB max)
      _showSnackbar('壓縮圖片中...', isLoading: true);
      final compressedBytes = await _compressImage(image);

      // Step 3: Upload to Supabase Storage
      _showSnackbar('上傳圖片...', isLoading: true);
      final imageUrl = await _uploadToStorage(compressedBytes, image.path);
      setState(() => _lastImageUrl = imageUrl);

      // Step 4: OCR - extract raw text + group by row
      final scanner = ref.read(receiptScannerProvider);
      final ocrResult = await scanner.scanFromFile(File(image.path));

      if (ocrResult.rawText.isEmpty) {
        _showError('未能識別文字，請重試');
        setState(() => _isProcessing = false);
        return;
      }

      // Build enhanced text: raw OCR + row-reconstructed structure
      // This helps LLM understand left-right column layout
      final ocrText = ocrResult.rawText;
      final reconstructed = ocrResult.reconstructedText;
      final enhancedText = '=== OCR Raw Text ===\n$ocrText\n\n=== Row-Reconstructed (左|右 format) ===\n$reconstructed';

      setState(() => _lastScannedText = ocrResult.rawText);

      // Step 5: LLM parse via Supabase Edge Function
      _showSnackbar('正在解析收據...', isLoading: true);
      final parseResult = await _callEdgeLLM(enhancedText);

      // Step 6: Save to DB (receipt header + items)
      await _saveReceiptToDb(
        imageUrl: imageUrl,
        rawText: ocrResult.rawText,
        parseResult: parseResult,
      );

      setState(() => _isProcessing = false);

      if (parseResult.isSuccess && parseResult.hasItems) {
        _showSuccessWithResult(parseResult);
      } else {
        _showError('已保存收據，但部分資料無法自動識別，請稍後手動補充');
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      final errStr = e.toString();
      if (errStr.contains('NO_ACTIVE_RELATION')) {
        _showRelationRequiredDialog();
      } else {
        _showError('Scan failed: $e');
      }
    }
  }

  /// Compress image to ~500KB max using flutter_image_compress
  Future<Uint8List> _compressImage(XFile image) async {
    final result = await FlutterImageCompress.compressWithFile(
      image.path,
      minWidth: 1200,
      minHeight: 1600,
      quality: 70,
      format: CompressFormat.jpeg,
    );

    if (result == null) {
      // Fallback: read original file
      return File(image.path).readAsBytesSync();
    }

    return result;
  }

  /// Upload compressed image to Supabase Storage, return public URL
  Future<String> _uploadToStorage(Uint8List bytes, String originalPath) async {
    final fileName = 'receipt_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final filePath = 'receipts/$fileName';

    try {
      await supabase.storage
          .from('receipts')
          .uploadBinary(filePath, bytes);
    } catch (e) {
      throw Exception('Upload failed: $e');
    }

    // Return public URL
    final url = supabase.storage.from('receipts').getPublicUrl(filePath);
    return url;
  }

  /// Call Supabase Edge Function for LLM parsing
  Future<ReceiptParseResult> _callEdgeLLM(String rawText) async {
    final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
    final anonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';

    String responseBody;
    try {
      final response = await http.post(
        Uri.parse('$supabaseUrl/functions/v1/receipt-parser'),
        headers: {
          'Content-Type': 'application/json',
          'apikey': anonKey,
          'Authorization': 'Bearer $anonKey',
        },
        body: jsonEncode({'raw_text': rawText}),
      );
      responseBody = response.body;

      if (response.statusCode != 200) {
        // Try to parse error JSON
        try {
          final errJson = jsonDecode(responseBody);
          throw Exception('Edge function error: ${errJson['error'] ?? responseBody}');
        } catch (_) {
          throw Exception('Edge function error: $responseBody');
        }
      }

      final json = jsonDecode(responseBody);

      // Check for error field OR if critical fields are null (LLM parse failed)
      if (json['error'] != null) {
        throw Exception('LLM parsing failed: ${json['error']}');
      }

      return ReceiptParseResult.fromJson(json);
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('LLM parsing failed: $e');
    }
  }

  /// Save receipt header + items to Supabase DB
  Future<void> _saveReceiptToDb({
    required String imageUrl,
    required String rawText,
    required ReceiptParseResult parseResult,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('Not logged in');

    // Get active relation
    final relations = await supabase
        .from('employer_helper_relations')
        .select('id, employer_id')
        .eq('helper_id', user.id)
        .eq('status', 'active')
        .maybeSingle();

    if (relations == null) {
      throw Exception('NO_ACTIVE_RELATION');
    }

    final receiptId = const Uuid().v4();
    final now = DateTime.now().millisecondsSinceEpoch;

    // Insert receipt header
    await supabase.from('receipts').insert({
      'id': receiptId,
      'employer_id': relations['employer_id'],
      'helper_id': user.id,
      'relation_id': relations['id'],
      'store_name': parseResult.storeName,
      'store_cate': parseResult.storeCate,
      'location': parseResult.location,
      'raw_text': rawText,
      'amount': parseResult.totalAmount,
      'transaction_date': parseResult.transactionDate,
      'image_local_path': imageUrl,
      'sync_status': 'pending',
      'local_timestamp': now,
      'created_at': DateTime.now().toIso8601String(),
    });

    // Insert receipt items
    if (parseResult.hasItems) {
      final itemRows = parseResult.items
          .map((item) => item.toMap(receiptId))
          .toList();

      await supabase.from('receipt_items').insert(itemRows);
    }

    // Trigger notification broadcast to employer via Edge Function
    try {
      await supabase.functions.invoke('notification-broadcast', body: {
        'type': 'INSERT',
        'table': 'receipts',
        'record': {
          'id': receiptId,
          'employer_id': relations['employer_id'],
          'helper_id': user.id,
          'relation_id': relations['id'],
          'store_name': parseResult.storeName,
          'amount': parseResult.totalAmount,
          'created_at': DateTime.now().toIso8601String(),
        },
      });
    } catch (e) {
      // Notification is non-critical, don't fail the save
      debugPrint('Notification broadcast failed: $e');
    }
  }

  void _showRelationRequiredDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: const Text('🔗 需要連接僱主'),
        content: const Text(
          '請先連接僱主才能保存收據。\n如果你已有代碼，請在上一個畫面輸入。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('確定'),
          ),
        ],
      ),
    );
  }

  void _showSuccessWithResult(ReceiptParseResult result) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                '✅ 收據已保存',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              if (result.storeName != null) _infoRow('店舖', result.storeName!),
              _infoRow('類別', result.storeCate),
              if (result.location != null) _infoRow('地區', result.location!),
              if (result.totalAmount != null)
                _infoRow('總金額', '\$${result.totalAmount!.toStringAsFixed(2)}'),
              const SizedBox(height: 16),
              Text(
                '📦 已識別 ${result.items.length} 件貨品',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...result.items.map((item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(child: Text(item.itemName)),
                        if (item.unitPrice != null)
                          Text('\$${item.unitPrice!.toStringAsFixed(1)}'),
                      ],
                    ),
                  )),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _captureAndScan();
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('再掃'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.check),
                      label: const Text('完成'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Receipt'),
        centerTitle: true,
        actions: [
          if (_lastScannedText != null)
            IconButton(
              icon: const Icon(Icons.history),
              onPressed: () {},
            ),
        ],
      ),
      body: _isInitialized
          ? Stack(
              children: [
                SizedBox.expand(
                  child: CameraPreview(_cameraController!),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.green.withValues(alpha: 0.5),
                          width: 2,
                        ),
                      ),
                      margin: const EdgeInsets.all(32),
                      child: const Center(
                        child: Text(
                          'Align receipt within frame',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            shadows: [
                              Shadow(
                                offset: Offset(1, 1),
                                blurRadius: 4,
                                color: Colors.black54,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_isProcessing)
                  Container(
                    color: Colors.black54,
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 16),
                          Text(
                            'Processing...',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            )
          : const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.camera_alt, size: 80, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('Initializing camera...'),
                  SizedBox(height: 8),
                  CircularProgressIndicator(),
                ],
              ),
            ),
      floatingActionButton: _isInitialized && !_isProcessing
          ? FloatingActionButton.large(
              onPressed: _captureAndScan,
              child: const Icon(Icons.camera_alt, size: 36),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

// ============================================================
// ReceiptParseResult (matches edge function JSON response)
// ============================================================

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

  factory ReceiptParseResult.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List? ?? [])
        .map((item) => ParsedItem.fromJson(item))
        .where((item) => item.itemName.isNotEmpty)
        .toList();

    return ReceiptParseResult(
      storeName: json['store_name'],
      storeCate: json['store_cate'] ?? 'other',
      location: json['location'],
      totalAmount: json['total_amount']?.toDouble(),
      transactionDate: json['transaction_date'],
      items: items,
      parseConfidence: (json['parse_confidence'] ?? 0.5).toDouble(),
      rawText: json['raw_text'] ?? '',
      isSuccess: json['error'] == null,
      errorMessage: json['error'],
    );
  }

  bool get hasItems => items.isNotEmpty;
}

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

  factory ParsedItem.fromJson(Map<String, dynamic> json) {
    return ParsedItem(
      itemName: json['item_name'] ?? '',
      itemRawText: json['item_raw_text'] ?? '',
      qty: (json['qty'] ?? 1).toDouble(),
      unitPrice: json['unit_price']?.toDouble(),
      prdCate: json['prd_cate'] ?? 'other',
    );
  }

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