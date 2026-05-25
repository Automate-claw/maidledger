import 'package:maidledger_localization/maidledger_localization.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
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
import '../../core/services/product_matching_service.dart';
import '../../core/services/shop_matching_service.dart';

/// Camera scan screen for receipt scanning
///
/// Workflow:
///   Phase 1 (Camera): Live preview → tap capture
///   Phase 2 (Preview): Show image + OCR text → [Retake] / [Confirm]
///   Phase 3 (Processing): Parallel compress+upload+LLM → Save → Result
enum ScanPhase { camera, preview, processing }

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  late final AppLocale _locale;

  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;

  // Phase state
  ScanPhase _scanPhase = ScanPhase.camera;

  // Preview state (Phase 2)
  XFile? _capturedImage;
  Uint8List? _compressedBytes;
  String? _ocrRawText;
  String? _ocrReconstructedText;
  String? _imageUrl; // pre-uploaded URL, ready for confirm

  // Processing state (Phase 3)
  bool _isProcessing = false;

  @override
  @override
  void initState() {
    super.initState();
    _locale = ref.read(localeProvider);
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

  Future<bool> _checkConnectivity() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      _showError('無網絡連接');
      return false;
    }
    return true;
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
  // PHASE 1 → PHASE 2: Capture → Show Preview + Run OCR + Compress in parallel
  // ============================================================

  Future<void> _onCapture() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    if (_isProcessing) return;

    try {
      // Step 1: Capture photo
      final XFile image = await _cameraController!.takePicture();

      setState(() {
        _capturedImage = image;
        _scanPhase = ScanPhase.preview;
        _ocrRawText = null;
        _ocrReconstructedText = null;
        _compressedBytes = null;
        _imageUrl = null;
      });

      // Step 2: Run OCR + Compress in parallel (background, non-blocking)
      _runOcrAndCompressInBackground(image);
    } catch (e) {
      _showError('Capture failed: $e');
    }
  }

  /// Run OCR + Compress in background after capture, before user confirms.
  /// Results populate _ocrRawText, _ocrReconstructedText, _compressedBytes.
  Future<void> _runOcrAndCompressInBackground(XFile image) async {
    // Parallel: OCR + Compress
    final results = await Future.wait([
      _runOcr(image),
      _compressImage(image),
    ]);

    final ocrResult = results[0] as OcrResult;
    final compressedBytes = results[1] as Uint8List;

    // After OCR completes, pre-upload to storage (background)
    // This makes confirm phase faster
    _uploadInBackground(compressedBytes, image.path);

    if (mounted) {
      setState(() {
        _ocrRawText = ocrResult.rawText;
        _ocrReconstructedText = ocrResult.reconstructedText;
        _compressedBytes = compressedBytes;
      });
    }
  }

  Future<OcrResult> _runOcr(XFile image) async {
    try {
      final scanner = ref.read(receiptScannerProvider);
      final result = await scanner.scanFromFile(File(image.path));
      return OcrResult(
        rawText: result.rawText,
        reconstructedText: result.reconstructedText,
      );
    } catch (e) {
      return OcrResult(rawText: '', reconstructedText: '');
    }
  }

  Future<void> _uploadInBackground(Uint8List bytes, String path) async {
    try {
      final url = await _uploadToStorage(bytes, path);
      if (mounted) {
        setState(() => _imageUrl = url);
      }
    } catch (e) {
      // Non-critical: upload can happen on confirm if not done yet
      debugPrint('Background upload failed (will retry on confirm): $e');
    }
  }

  // ============================================================
  // PHASE 2: Preview → User decides Retake or Confirm
  // ============================================================

  Future<void> _onRetake() async {
    if (_isProcessing) return;

    setState(() {
      _capturedImage = null;
      _ocrRawText = null;
      _ocrReconstructedText = null;
      _compressedBytes = null;
      _imageUrl = null;
      _scanPhase = ScanPhase.camera;
    });

    // Re-initialize camera if needed
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      await _initCamera();
    }
  }

  Future<void> _onConfirm() async {
    if (_isProcessing) return;
    if (_capturedImage == null) return;

    if (!await _checkConnectivity()) return;

    // Fire-and-forget: save receipt immediately, return to camera < 1s
    // LLM parse + matching runs in background via receipt-processor cron
    try {
      // Ensure we have compressed bytes (should be ready from background)
      Uint8List? bytes = _compressedBytes;
      String? imageUrl = _imageUrl;

      // If background upload didn't complete, do it now (blocking but fast)
      if (bytes == null || imageUrl == null) {
        bytes ??= await _compressImage(_capturedImage!);
        imageUrl ??= await _uploadToStorage(bytes, _capturedImage!.path);
      }

      final rawText = _ocrRawText ?? '';
      final reconstructed = _ocrReconstructedText ?? '';

      if (rawText.isEmpty) {
        _showError('未能識別文字，請重新拍攝');
        await _onRetake();
        return;
      }

      // Immediate save: parse_status=pending, background job does LLM later
      await _saveReceiptImmediate(
        imageUrl: imageUrl,
        rawText: rawText,
        reconstructedText: reconstructed,
      );

      // Instant return to camera - user can continue scanning
      setState(() {
        _capturedImage = null;
        _ocrRawText = null;
        _ocrReconstructedText = null;
        _compressedBytes = null;
        _imageUrl = null;
        _scanPhase = ScanPhase.camera;
        _isProcessing = false;
      });

      _showSnackbar('已保存，後台處理緊...', isLoading: false);
    } catch (e) {
      setState(() => _isProcessing = false);
      final errStr = e.toString();
      if (errStr.contains('NO_ACTIVE_RELATION')) {
        _showRelationRequiredDialog();
      } else {
        _showError('儲存失敗: $e');
      }
    }
  }

  /// Save receipt immediately and trigger LLM parsing via receipt-orchestrate.
  /// Flow: insert → call receipt-orchestrate → user returns to camera.
  /// Backend handles: receipt-vision → shop-manager → product-manager → receipt-writer.
  Future<void> _saveReceiptImmediate({
    required String imageUrl,
    required String rawText,
    required String reconstructedText,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('Not logged in');

    final relations = await supabase
        .from('employer_helper_relations')
        .select('id, employer_id')
        .eq('helper_id', user.id)
        .eq('status', 'active')
        .maybeSingle();

    final receiptId = const Uuid().v4();
    final now = DateTime.now().millisecondsSinceEpoch;

    // Step 1: Immediate write to DB with image URL
    await supabase.from('receipts').insert({
      'id': receiptId,
      'employer_id': relations?['employer_id'],
      'helper_id': user.id,
      'relation_id': relations?['id'],
      'raw_text': rawText,
      'ocr_raw_text': rawText,
      'ocr_reconstructed': reconstructedText,
      'image_local_path': imageUrl,
      'sync_status': 'pending',
      'local_timestamp': now,
      'parse_status': 'pending',
      'created_at': DateTime.now().toIso8601String(),
    });

    // Step 2: Immediately trigger receipt-orchestrate (receipt-vision → write)
    _triggerReceiptOrchestrate(receiptId);
  }

  Future<void> _triggerReceiptOrchestrate(String receiptId) async {
    // Fire-and-forget: trigger backend processing, don't wait for result
    try {
      final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
      final serviceKey = dotenv.env['SUPABASE_SERVICE_ROLE_KEY'] ?? '';

      await http.post(
        Uri.parse('$supabaseUrl/functions/v1/receipt-orchestrate'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $serviceKey',
        },
        body: jsonEncode({'receipt_id': receiptId}),
      );
    } catch (e) {
      // Non-critical: receipt is saved, orchestration can be retried via cron
      debugPrint('receipt-orchestrate trigger failed (will retry via cron): $e');
    }
  }

  // ============================================================
  // Core helpers
  // ============================================================

  Future<Uint8List> _compressImage(XFile image) async {
    final result = await FlutterImageCompress.compressWithFile(
      image.path,
      minWidth: 1200,
      minHeight: 1600,
      quality: 70,
      format: CompressFormat.jpeg,
    );
    if (result == null) return File(image.path).readAsBytesSync();
    return result;
  }

  Future<String> _uploadToStorage(Uint8List bytes, String originalPath) async {
    final fileName = 'receipt_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final filePath = 'receipts/$fileName';
    await supabase.storage.from('receipts').uploadBinary(filePath, bytes);
    return supabase.storage.from('receipts').getPublicUrl(filePath);
  }

  Future<ReceiptParseResult> _callEdgeLLM(String rawText, String reconstructedText) async {
    final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
    final anonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';

    try {
      final response = await http.post(
        Uri.parse('$supabaseUrl/functions/v1/receipt-parser'),
        headers: {
          'Content-Type': 'application/json',
          'apikey': anonKey,
          'Authorization': 'Bearer $anonKey',
        },
        body: jsonEncode({
          'raw_text': rawText,
          'reconstructed_text': reconstructedText,
        }),
      );

      if (response.statusCode != 200) {
        try {
          final errJson = jsonDecode(response.body);
          throw Exception('Edge function error: ${errJson['error'] ?? response.body}');
        } catch (_) {
          throw Exception('Edge function error: ${response.body}');
        }
      }

      final json = jsonDecode(response.body);
      if (json['error'] != null) {
        throw Exception('LLM parsing failed: ${json['error']}');
      }

      return ReceiptParseResult.fromJson(json);
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('LLM parsing failed: $e');
    }
  }

  Future<void> _saveReceiptToDb({
    required String imageUrl,
    required String rawText,
    required ReceiptParseResult parseResult,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('Not logged in');

    final relations = await supabase
        .from('employer_helper_relations')
        .select('id, employer_id')
        .eq('helper_id', user.id)
        .eq('status', 'active')
        .maybeSingle();

    final receiptId = const Uuid().v4();
    final now = DateTime.now().millisecondsSinceEpoch;

    await supabase.from('receipts').insert({
      'id': receiptId,
      'employer_id': relations?['employer_id'],
      'helper_id': user.id,
      'relation_id': relations?['id'],
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

    final productMatcher = ProductMatchingService(supabase);
    if (parseResult.hasItems) {
      final itemRows = parseResult.items.map((item) => item.toMap(receiptId)).toList();
      await supabase.from('receipt_items').insert(itemRows);

      for (var i = 0; i < parseResult.items.length; i++) {
        final item = parseResult.items[i];
        try {
          final match = await productMatcher.matchItem(
            itemName: item.itemRawText.isNotEmpty ? item.itemRawText : item.itemName,
            prdCate: item.prdCate,
          );
          if (match != null) {
            final itemRow = await supabase
                .from('receipt_items')
                .select('id')
                .eq('receipt_id', receiptId)
                .eq('item_name', item.itemName)
                .maybeSingle();
            if (itemRow != null) {
              await productMatcher.bindReceiptItem(itemRow['id'] as String, match.masterProductId);
            }
          } else {
            // No match — create master product and update receipt_items
            final created = await productMatcher.createMasterProduct(
              rawName: item.itemName,  // use translated name as canonical
              prdCate: item.prdCate,
              defaultUnit: '件',
            );
            final itemRow = await supabase
                .from('receipt_items')
                .select('id')
                .eq('receipt_id', receiptId)
                .eq('item_name', item.itemName)
                .maybeSingle();
            if (itemRow != null) {
              await productMatcher.bindReceiptItem(itemRow['id'] as String, created.masterProductId);
            }
            // Also create alias from raw text for future matching
            if (item.itemRawText.isNotEmpty && item.itemRawText != item.itemName) {
              await supabase.from('product_aliases').upsert({
                'raw_name': item.itemRawText,
                'master_product_id': created.masterProductId,
                'source': 'scan',
              });
            }
          }
        } catch (e) {
          debugPrint('Product matching error for "${item.itemName}": $e');
        }
      }
    }

    // ── Phase 2: Shop matching ──
    String? shopId;
    if (parseResult.storeName != null && parseResult.storeName!.isNotEmpty) {
      final shopService = ShopMatchingService(supabase);
      final shopResult = await shopService.matchShop(
        rawShopName: parseResult.storeName!,
        shopType: parseResult.storeCate,
      );
      shopId = shopResult?.shopId;
      if (shopResult != null && shopId != null) {
        await supabase.from('receipts').update({'shop_id': shopId}).eq('id', receiptId);
      }
    }

    // ── Phase 3: Write price_history for each item ──
    // Use master_product_id already bound to receipt_items in Phase 1
    final receiptItems = await supabase
        .from('receipt_items')
        .select('id, item_name, master_product_id, unit_price, line_total')
        .eq('receipt_id', receiptId);

    for (final itemRow in receiptItems) {
      final masterProductId = itemRow['master_product_id'] as String?;
      if (masterProductId == null) {
        debugPrint('Phase 3: receipt_item ${itemRow['id']} has no master_product_id, skipping price_history');
        continue;
      }

      final price = (itemRow['line_total'] as num?)?.toDouble();
      if (price == null) {
        debugPrint('Phase 3: receipt_item ${itemRow['id']} has no line_total, skipping price_history');
        continue;
      }

      try {
        await supabase.from('price_history').insert({
          'master_product_id': masterProductId,
          'shop_id': shopId,
          'location': parseResult.location,
          'price': price,
          'original_price': itemRow['unit_price'],
          'total_paid': itemRow['unit_price'],
          'unit': '件',
          'source_receipt_id': receiptId,
          'recorded_at': DateTime.now().toIso8601String().split('T')[0],
        });
      } catch (e) {
        debugPrint('Phase 3 price_history insert error: $e');
        await _logAppError('price_history_insert', 'scan', e.toString(), {
          'receipt_id': receiptId,
          'receipt_item_id': itemRow['id'],
          'master_product_id': masterProductId,
        });
      }
    }

    final empId = relations?['employer_id'];
    if (empId != null) {
      try {
        await supabase.functions.invoke('notification-broadcast', body: {
          'type': 'INSERT',
          'table': 'receipts',
          'record': {
            'id': receiptId,
            'employer_id': empId,
            'helper_id': user.id,
            'relation_id': relations!['id'],
            'store_name': parseResult.storeName,
            'amount': parseResult.totalAmount,
            'created_at': DateTime.now().toIso8601String(),
          },
        });
      } catch (e) {
        debugPrint('Notification broadcast failed: $e');
      }
    }
  }

  void _showRelationRequiredDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: Text('🔗 ${AppStrings.needLinkEmployer(_locale)}'),
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
              Text('✅ ${AppStrings.expenseSaved(_locale)}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              if (result.storeName != null) _infoRow('店舖', result.storeName!),
              _infoRow('類別', result.storeCate),
              if (result.location != null) _infoRow('地區', result.location!),
              if (result.totalAmount != null)
                _infoRow('總金額', '\$${result.totalAmount!.toStringAsFixed(2)}'),
              const SizedBox(height: 16),
              Text('📦 已識別 ${result.items.length} 件貨品', style: const TextStyle(fontWeight: FontWeight.bold)),
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
                        _onRetake();
                      },
                      icon: const Icon(Icons.refresh),
                      label: Text(AppStrings.scan(_locale)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.check),
                      label: Text(AppStrings.confirm(_locale)),
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

  Future<void> _logAppError(String errorType, String source, String message, Map<String, dynamic> extra) async {
    try {
      await supabase.from('app_errors').insert({
        'error_type': errorType,
        'source': source,
        'message': message,
        'extra_data': extra,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('_logAppError failed: $e');
    }
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
        title: Text(_getTitle()),
        centerTitle: true,
      ),
      body: _buildBody(),
      floatingActionButton: _scanPhase == ScanPhase.camera && _isInitialized && !_isProcessing
          ? FloatingActionButton.large(
              onPressed: _onCapture,
              child: const Icon(Icons.camera_alt, size: 36),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  String _getTitle() {
    switch (_scanPhase) {
      case ScanPhase.camera:
        return AppStrings.scan(_locale);
      case ScanPhase.preview:
        return AppStrings.confirmExpense(_locale);
      case ScanPhase.processing:
        return AppStrings.aiThinking(_locale);
    }
  }

  Widget _buildBody() {
    switch (_scanPhase) {
      case ScanPhase.camera:
        return _buildCameraBody();
      case ScanPhase.preview:
        return _buildPreviewBody();
      case ScanPhase.processing:
        return _buildProcessingBody();
    }
  }

  // ============================================================
  // PHASE 1: Camera Live Preview
  // ============================================================

  Widget _buildCameraBody() {
    if (!_isInitialized) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.camera_alt, size: 80, color: Colors.grey),
            SizedBox(height: 16),
            const Text('Initializing camera...'),
            SizedBox(height: 8),
            CircularProgressIndicator(),
          ],
        ),
      );
    }

    return Stack(
      children: [
        SizedBox.expand(child: CameraPreview(_cameraController!)),
        // Receipt alignment guide
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.green.withValues(alpha: 0.5), width: 2),
              ),
              margin: const EdgeInsets.all(32),
              child: Center(
                child: Text(
                  AppStrings.alignReceipt(_locale),
                  style: TextStyle(

                    color: Colors.white,
                    fontSize: 16,
                    shadows: [Shadow(offset: Offset(1, 1), blurRadius: 4, color: Colors.black54)],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // PHASE 2: Preview with OCR Text + Retake / Confirm buttons
  // ============================================================

  Widget _buildPreviewBody() {
    if (_capturedImage == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final imageBytes = File(_capturedImage!.path).readAsBytesSync();

    return Column(
      children: [
        // Image preview (tappable to zoom)
        Expanded(
          flex: 3,
          child: GestureDetector(
            onTap: () => _showImageFullScreen(imageBytes),
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                image: DecorationImage(
                  image: MemoryImage(imageBytes),
                  fit: BoxFit.contain,
                ),
              ),
              child: Stack(
                children: [
                  // Quality indicator badge
                  Positioned(
                    top: 12,
                    right: 12,
                    child: _buildQualityBadge(),
                  ),
                ],
              ),
            ),
          ),
        ),

        // OCR Text section
        Expanded(
          flex: 2,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.text_fields, size: 16, color: Colors.grey),
                    const SizedBox(width: 6),
                    Text(
                      '📝 識別文字',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                      ),
                    ),
                    const Spacer(),
                    if (_ocrRawText == null)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else if (_ocrRawText!.isEmpty)
                      Text(
                        '⚠️ 未識別到文字',
                        style: TextStyle(fontSize: 12, color: Colors.orange[700]),
                      )
                    else
                      Text(
                        '✓ 已識別',
                        style: TextStyle(fontSize: 12, color: Colors.green[700]),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _ocrRawText != null
                      ? SingleChildScrollView(
                          child: Text(
                            _ocrRawText!.isEmpty
                                ? '（未能識別文字，請嘗試重新拍攝）'
                                : _ocrRawText!,
                            style: TextStyle(
                              fontSize: 12,
                              color: _ocrRawText!.isEmpty ? Colors.grey : Colors.black87,
                              fontFamily: 'monospace',
                            ),
                          ),
                        )
                      : const Center(child: Text('正在識別文字...', style: TextStyle(color: Colors.grey))),
                ),
              ],
            ),
          ),
        ),

        // Action buttons
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isProcessing ? null : _onRetake,
                  icon: const Icon(Icons.refresh),
                  label: Text(AppStrings.scan(_locale)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: (_isProcessing || _ocrRawText == null) ? null : _onConfirm,
                  icon: const Icon(Icons.check),
                  label: Text(AppStrings.confirm(_locale)),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQualityBadge() {
    // Show "Clear" / "Blurry" based on OCR confidence
    final hasText = _ocrRawText != null && _ocrRawText!.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: hasText ? Colors.green : Colors.orange,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(hasText ? Icons.check_circle : Icons.warning, size: 12, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            hasText ? '清晰' : '模糊',
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  void _showImageFullScreen(Uint8List imageBytes) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            InteractiveViewer(
              child: Image.memory(imageBytes, fit: BoxFit.contain),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // PHASE 3: Processing indicator
  // ============================================================

  Widget _buildProcessingBody() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          const Text(
            '正在處理...',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            '壓縮 → 上傳 → AI 分析',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Local data classes
// ============================================================

class OcrResult {
  final String rawText;
  final String reconstructedText;
  OcrResult({required this.rawText, required this.reconstructedText});
}

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

  double? get lineTotal => (unitPrice != null && qty > 0) ? unitPrice! * qty : null;

  static const _validCategories = {
    'fish', 'pork', 'beef', 'chicken', 'vegetables', 'rice',
    'oil', 'seasoning', 'snack', 'drink', 'daily', 'other',
  };

  Map<String, dynamic> toMap(String receiptId) {
    final safeCate = _validCategories.contains(prdCate) ? prdCate : 'other';
    return {
      'receipt_id': receiptId,
      'item_name': itemName,
      'item_raw_text': itemRawText,
      'qty': qty,
      'unit_price': unitPrice,
      'prd_cate': safeCate,
      'line_total': lineTotal,
    };
  }
}
