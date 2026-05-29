import 'package:maidledger_localization/maidledger_localization.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:intl/intl.dart';
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
import '../../core/providers/navigation_provider.dart';

/// Camera scan screen for receipt scanning
///
/// Workflow:
///   Phase 1 (Camera): Live preview → tap capture
///   Phase 2 (Preview): Show image + OCR text → [Retake] / [Confirm]
///   Phase 3 (Processing): Parallel compress+upload+LLM → Save → Result
enum ScanPhase { camera, preview, processing, success, failed }

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> with WidgetsBindingObserver {
  AppLocale get _locale => ref.watch(localeProvider);

  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isInitializing = false;
  bool _disposed = false;
  bool _pendingDispose = false; // true when disposal is in progress
  bool _isVisible = true;

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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Don't init camera here - didChangeDependencies will handle it
    // This avoids double-init race conditions
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('[ScanScreen] didChangeAppLifecycleState: $state');
    final activeTab = ref.read(activeTabProvider);
    // Only manage camera if we're on the scan tab
    if (activeTab != 0) return;
    
    // Dispose camera when app goes to background or becomes inactive
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _disposeCamera();
    } else if (state == AppLifecycleState.resumed && _scanPhase == ScanPhase.camera) {
      // Reinitialize camera when app resumes to camera phase
      if (!_isInitialized && !_isInitializing) {
        _initCamera();
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final activeTab = ref.watch(activeTabProvider);
    print('[ScanScreen] didChangeDependencies: activeTab=$activeTab, _isInitialized=$_isInitialized, _isInitializing=$_isInitializing, _scanPhase=$_scanPhase');
    
    if (activeTab != 0) {
      // Switching away from scan tab - dispose camera
      print('[ScanScreen] Tab away - disposing camera');
      _disposeCamera();
    } else {
      // On scan tab - init camera if needed
      // Reset _disposed so any in-flight init can proceed
      _disposed = false;
      
      if (_isInitialized && _cameraController != null && _cameraController!.value.isInitialized) {
        print('[ScanScreen] Camera already ready, skipping init');
        return; // Camera already ready
      }
      
      if (!_isInitialized && !_isInitializing && _scanPhase == ScanPhase.camera) {
        print('[ScanScreen] Guard passed, calling _initCamera()');
        _initCamera();
      } else {
        print('[ScanScreen] Guard failed: _isInitialized=$_isInitialized, _isInitializing=$_isInitializing, _scanPhase=$_scanPhase');
        // Force reset everything and retry in next frame
        WidgetsBinding.instance.addPostFrameCallback((_) {
          print('[ScanScreen] Post-frame: Force resetting all state and retrying _initCamera()');
          _isInitializing = false;
          _isInitialized = false;
          _disposed = false;
          _initCamera();
        });
      }
    }
  }

  void _disposeCamera() {
    _disposed = true;
    _pendingDispose = true;
    
    if (_cameraController != null) {
      final controller = _cameraController!;
      _cameraController = null;
      _isInitialized = false;
      
      // Dispose asynchronously but we don't wait
      controller.dispose().then((_) {
        _pendingDispose = false;
      }).catchError((_) {
        _pendingDispose = false;
      });
    } else {
      _pendingDispose = false;
    }
  }

  Future<void> _initCamera() async {
    // Prevent concurrent initialization
    if (_isInitializing) {
      print('[ScanScreen] _initCamera skipped: already initializing');
      return;
    }
    
    // Safety timeout: force reset after 10 seconds
    final timeout = Future.delayed(const Duration(seconds: 10), () {
      if (_isInitializing) {
        print('[ScanScreen] TIMEOUT: force resetting _isInitializing');
        _isInitializing = false;
        _disposed = true;
      }
    });
    
    // Mark as disposed - if tab switches away during init, this will be true
    _disposed = false;
    _isInitializing = true;
    print('[ScanScreen] _initCamera started');

    try {
      // Dispose existing controller before creating new one
      if (_cameraController != null) {
        try {
          await _cameraController!.dispose();
        } catch (_) {}
        _cameraController = null;
      }

      // Check if we were disposed while waiting
      if (_disposed) {
        _isInitializing = false;
        return;
      }

      final cameras = await availableCameras();
      
      // Check again after await
      if (_disposed) {
        _isInitializing = false;
        return;
      }

      if (cameras == null || cameras.isEmpty) {
        if (!_disposed && mounted) {
          _showError('No cameras available');
        }
        _isInitializing = false;
        return;
      }

      final backCamera = cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      // Check one more time before initialize
      if (_disposed) {
        controller.dispose();
        _isInitializing = false;
        return;
      }

      await controller.initialize();

      // Final check before setting state
      if (_disposed) {
        controller.dispose();
        _isInitializing = false;
        return;
      }

      _cameraController = controller;
      if (mounted) {
        setState(() => _isInitialized = true);
      }
    } catch (e) {
      // Only show error if we're still the active tab and not disposed
      if (!_disposed && mounted && !_pendingDispose) {
        _showError('Camera initialization failed: $e');
      }
    } finally {
      _isInitializing = false;
      _disposed = false;
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
        _compressedBytes = null;
        _imageUrl = null;
      });

      // Step 2: Compress in background (preparing for upload when confirmed)
      _compressInBackground(image);
    } catch (e) {
      _showError('Capture failed: $e');
    }
  }

  Future<void> _compressInBackground(XFile image) async {
    try {
      final compressed = await _compressImage(image);
      if (mounted) {
        setState(() => _compressedBytes = compressed);
      }
    } catch (e) {
      debugPrint('Background compress failed: $e');
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

    setState(() => _isProcessing = true);

    // Show processing state
    setState(() => _scanPhase = ScanPhase.processing);

    try {
      // Compress + upload
      Uint8List? bytes = _compressedBytes;
      String? imageUrl = _imageUrl;
      if (bytes == null || imageUrl == null) {
        bytes ??= await _compressImage(_capturedImage!);
        imageUrl ??= await _uploadToStorage(bytes, _capturedImage!.path);
      }

      await _saveReceiptImmediate(
        imageUrl: imageUrl,
        rawText: '',
        reconstructedText: '',
      );

      // Success: full-page feedback, 3.5s delay, then return to camera
      setState(() => _scanPhase = ScanPhase.success);
      await Future.delayed(const Duration(milliseconds: 3500));
      if (!mounted) return;
      _returnToCamera();
    } catch (e) {
      final errStr = e.toString();
      if (errStr.contains('NO_ACTIVE_RELATION')) {
        _showRelationRequiredDialog();
        _returnToCamera();
      } else {
        setState(() => _scanPhase = ScanPhase.failed);
        _isProcessing = false;
      }
    }
  }

  void _returnToCamera() {
    setState(() {
      _capturedImage = null;
      _ocrRawText = null;
      _ocrReconstructedText = null;
      _compressedBytes = null;
      _imageUrl = null;
      _scanPhase = ScanPhase.camera;
      _isProcessing = false;
    });
  }

  Future<bool> _onWillPop() async {
    if (_scanPhase == ScanPhase.success || _scanPhase == ScanPhase.failed) {
      _returnToCamera();
      return false;
    }
    return true;
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
      'transaction_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
      'date_anomaly': false,
      'created_by': user.id,
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
    WidgetsBinding.instance.removeObserver(this);
    _disposeCamera();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Check if we are the active tab
    final activeTab = ref.watch(activeTabProvider);
    print('[ScanScreen] build: activeTab=$activeTab');
    
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && (_scanPhase == ScanPhase.success || _scanPhase == ScanPhase.failed)) {
          _returnToCamera();
        }
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(_getTitle()),
        centerTitle: true,
      ),
      body: activeTab != 0
          ? _buildPlaceholderBody()
          : _buildBody(),
      floatingActionButton: _scanPhase == ScanPhase.camera && _isInitialized && !_isProcessing
          ? FloatingActionButton.large(
              onPressed: _onCapture,
              child: const Icon(Icons.camera_alt, size: 36),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      ),
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
      case ScanPhase.success:
        return AppStrings.uploadSuccess(_locale);
      case ScanPhase.failed:
        return AppStrings.uploadFailed(_locale);
    }
  }

  Widget _buildPlaceholderBody() {
    // When switching away from scan tab, dispose camera and show placeholder
    if (_cameraController != null) {
      _disposeCamera();
    }
    return const SizedBox.shrink();
  }

  Widget _buildBody() {
    switch (_scanPhase) {
      case ScanPhase.camera:
        return _buildCameraBody();
      case ScanPhase.preview:
        return _buildPreviewBody();
      case ScanPhase.processing:
        return _buildProcessingBody();
      case ScanPhase.success:
        return _buildSuccessBody();
      case ScanPhase.failed:
        return _buildFailedBody();
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
  // PHASE 2: Image preview — user judges clarity → Confirm
  // ============================================================
  Widget _buildPreviewBody() {
    if (_capturedImage == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final imageBytes = File(_capturedImage!.path).readAsBytesSync();

    return Column(
      children: [
        // Image preview (tappable to zoom full screen)
        Expanded(
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
            ),
          ),
        ),

        // Action buttons
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isProcessing ? null : _onRetake,
                  icon: const Icon(Icons.refresh),
                  label: Text(AppStrings.scan(_locale)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isProcessing ? null : _onConfirm,
                  icon: const Icon(Icons.check),
                  label: Text(AppStrings.confirm(_locale)),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
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
  // SUCCESS — fire-and-forget, 3.5s auto-return
  // ============================================================
  Widget _buildSuccessBody() {
    return Container(
      color: Colors.green[50],
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, size: 80, color: Colors.green[600]),
              const SizedBox(height: 24),
              Text(
                AppStrings.uploadSuccess(_locale),
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.green[800]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                AppStrings.uploadSuccessDesc(_locale),
                style: TextStyle(fontSize: 16, color: Colors.green[700]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              OutlinedButton(
                onPressed: () { if (mounted) _returnToCamera(); },
                child: Text(AppStrings.scan(_locale)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // FAILED — explain error, allow retry
  // ============================================================
  Widget _buildFailedBody() {
    return Container(
      color: Colors.red[50],
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 80, color: Colors.red[600]),
              const SizedBox(height: 24),
              Text(
                AppStrings.uploadFailed(_locale),
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.red[800]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                AppStrings.uploadFailedRetry(_locale),
                style: TextStyle(fontSize: 16, color: Colors.red[700]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () { if (mounted) _returnToCamera(); },
                child: Text(AppStrings.scan(_locale)),
              ),
            ],
          ),
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
