import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maidledger_localization/maidledger_localization.dart';
import '../../core/services/supabase_client_provider.dart';

/// Receipt detail screen — shows photo, items, editable fields
class ReceiptDetailScreen extends ConsumerStatefulWidget {
  final String receiptId;

  const ReceiptDetailScreen({super.key, required this.receiptId});

  @override
  ConsumerState<ReceiptDetailScreen> createState() => _ReceiptDetailScreenState();
}

class _ReceiptDetailScreenState extends ConsumerState<ReceiptDetailScreen> {
  AppLocale get _locale => ref.watch(localeProvider);
  Map<String, dynamic>? _receipt;
  List<Map<String, dynamic>> _items = [];
  Map<String, Map<String, String>> _prdCategories = {}; // code → {tc, en}
  bool _isLoading = true;
  String? _error;
  bool _isSaving = false;
  AppLocale get _locale => ref.watch(localeProvider);

  late TextEditingController _storeNameController;
  late TextEditingController _locationController;
  late TextEditingController _amountController;
  DateTime? _transactionDate;
  String _storeCate = 'other';

  @override
  void initState() {
    super.initState();
    _storeNameController = TextEditingController();
    _locationController = TextEditingController();
    _amountController = TextEditingController();
    _loadReceipt();
  }

  @override
  void dispose() {
    _storeNameController.dispose();
    _locationController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadReceipt() async {
    setState(() => _isLoading = true);
    try {
      final receiptRes = await supabase
          .from('receipts')
          .select()
          .eq('id', widget.receiptId)
          .maybeSingle();

      if (receiptRes == null) {
        setState(() {
          _error = 'Receipt not found';
          _isLoading = false;
        });
        return;
      }

      // Load prd_categories lookup (for display names)
      final cateRes = await supabase.from('prd_categories').select('code, name_tc, name_en');
      final cateMap = <String, Map<String, String>>{};
      for (final row in cateRes as List) {
        cateMap[row['code'] as String] = {
          'tc': row['name_tc'] as String,
          'en': row['name_en'] as String? ?? row['name_tc'] as String,
        };
      }

      final itemsRes = await supabase
          .from('receipt_items')
          .select()
          .eq('receipt_id', widget.receiptId)
          .order('created_at');

      _storeNameController.text = receiptRes['store_name'] ?? '';
      _locationController.text = receiptRes['location'] ?? '';
      _amountController.text = receiptRes['amount']?.toString() ?? '';
      _transactionDate = DateTime.tryParse(receiptRes['transaction_date'] ?? '');
      _storeCate = receiptRes['store_cate'] ?? 'other';

      // Merge category display names into each item
      final itemsWithCate = (itemsRes as List).map((item) {
        final code = item['prd_cate'] as String? ?? 'other';
        final names = cateMap[code] ?? {'tc': code, 'en': code};
        return Map<String, dynamic>.from(item)
          ..['prd_cate_name_tc'] = names['tc']
          ..['prd_cate_name_en'] = names['en'];
      }).toList();

      setState(() {
        _receipt = Map<String, dynamic>.from(receiptRes);
        _items = itemsWithCate;
        _prdCategories = cateMap;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _saveChanges() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final amount = double.tryParse(_amountController.text);

      await supabase.from('receipts').update({
        'store_name': _storeNameController.text.trim(),
        'store_cate': _storeCate,
        'location': _locationController.text.trim(),
        'amount': amount,
        'transaction_date': _transactionDate?.toIso8601String().split('T').first,
      }).eq('id', widget.receiptId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.itemSaved(_locale)), backgroundColor: Colors.green),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ ${AppStrings.saveFailed(_locale)}'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _updateItem(int index, Map<String, dynamic> updatedItem) async {
    try {
      await supabase.from('receipt_items').update({
        'item_name': updatedItem['item_name'],
        'qty': updatedItem['qty'],
        'unit_price': updatedItem['unit_price'],
        'prd_cate': updatedItem['prd_cate'],
        'line_total': updatedItem['line_total'],
      }).eq('id', updatedItem['id']);

      setState(() => _items[index] = updatedItem);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ ${AppStrings.updateFailed(_locale)}'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteReceipt() async {
    if (_receipt == null) return;
    try {
      // Delete storage image first
      final imagePath = _receipt!['image_local_path'] as String?;
      if (imagePath != null && imagePath.contains('receipts/')) {
        try {
          await supabase.storage.from('receipts').remove([imagePath]);
        } catch (e) {
          debugPrint('Storage delete error (ignoring): $e');
        }
      }
      // Delete receipt (cascades to receipt_items via FK)
      final result = await supabase.from('receipts').delete().eq('id', widget.receiptId);
      debugPrint('Delete result type: ${result.runtimeType} value: $result');
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      debugPrint('Delete receipt error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('刪除失敗： $e')),
        );
      }
    }
  }


  void _confirmDeleteReceipt() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.deleteReceipt(_locale)),
        content: Text(AppStrings.deleteReceiptConfirm(_locale)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppStrings.cancel(_locale)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              _deleteReceipt();
            },
            child: Text(AppStrings.delete(_locale)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteItem(int index) async {
    final item = _items[index];
    try {
      await supabase.from('receipt_items').delete().eq('id', item['id']);
      setState(() => _items.removeAt(index));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ ${AppStrings.deleteFailed(_locale)}'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.receiptDetail(_locale)),
        actions: [
          if (!_isLoading)
            TextButton.icon(
              onPressed: _isSaving ? null : _saveChanges,
              icon: _isSaving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: Text(_isSaving ? AppStrings.saving(_locale) : AppStrings.save(_locale)),
            ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: () => _confirmDeleteReceipt(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('❌ $_error'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_receipt?['date_anomaly'] == true) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange[200]!),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, color: Colors.orange[700], size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '⚠️ 系統懷疑這筆交易的日期有誤，請確認是否正確',
                                  style: TextStyle(color: Colors.orange[900], fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      _buildPhotoSection(),
                      const SizedBox(height: 24),
                      _buildSectionTitle(AppStrings.storeInfo(_locale)),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _storeNameController,
                        decoration: InputDecoration(
                          labelText: AppStrings.storeName(_locale),
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.store),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _storeCate,
                        decoration: InputDecoration(
                          labelText: AppStrings.storeCategory(_locale),
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.category),
                        ),
                        items: [
                          DropdownMenuItem(value: 'supermarket', child: Text(AppStrings.supermarket(_locale))),
                          DropdownMenuItem(value: 'wet_market', child: Text(AppStrings.wetMarket(_locale))),
                          DropdownMenuItem(value: 'pharmacy', child: Text(AppStrings.pharmacy(_locale))),
                          DropdownMenuItem(value: 'convenience', child: Text(AppStrings.convenience(_locale))),
                          DropdownMenuItem(value: 'online', child: Text(AppStrings.online(_locale))),
                          DropdownMenuItem(value: 'restaurant', child: Text(AppStrings.restaurant(_locale))),
                          DropdownMenuItem(value: 'cafe', child: Text(AppStrings.cafe(_locale))),
                          DropdownMenuItem(value: 'takeaway', child: Text(AppStrings.takeaway(_locale))),
                          DropdownMenuItem(value: 'other', child: Text(AppStrings.otherStore(_locale))),
                        ],
                        onChanged: (v) => setState(() => _storeCate = v ?? 'other'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _locationController,
                        decoration: InputDecoration(
                          labelText: AppStrings.location(_locale),
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.location_on),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _buildSectionTitle(AppStrings.amountDate(_locale)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _amountController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: AppStrings.amount(_locale),
                                border: const OutlineInputBorder(),
                                prefixIcon: const Icon(Icons.attach_money),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: InkWell(
                              onTap: _pickDate,
                              child: InputDecorator(
                                decoration: InputDecoration(
                                  labelText: AppStrings.date(_locale),
                                  border: const OutlineInputBorder(),
                                  prefixIcon: const Icon(Icons.calendar_today),
                                ),
                                child: Text(
                                  _transactionDate != null
                                      ? '${_transactionDate!.year}-${_transactionDate!.month.toString().padLeft(2, '0')}-${_transactionDate!.day.toString().padLeft(2, '0')}'
                                      : AppStrings.selectDate(_locale),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _buildSectionTitle(AppStrings.itemDetails(_locale)),
                      const SizedBox(height: 12),
                      if (_items.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(AppStrings.noItems(_locale), style: TextStyle(color: Colors.grey)),
                          ),
                        )
                      else
                        ...List.generate(_items.length, (i) => _buildItemCard(i)),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold));
  }

  Widget _buildPhotoSection() {
    final imagePath = _receipt?['image_local_path'] as String?;

    if (imagePath == null || imagePath.isEmpty) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.receipt_long, size: 48, color: Colors.grey),
              SizedBox(height: 8),
              Text(AppStrings.noReceiptPhoto(_locale), style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    final isNetwork = imagePath.startsWith('http');
    // isBase64: data:image URI OR long string with no protocol marker
    final isBase64 = imagePath.startsWith('data:image') || (imagePath.length > 100 && !imagePath.contains('://'));

    return GestureDetector(
      onTap: () => _openFullscreenImage(context, imagePath),
      child: Hero(
        tag: 'receipt_image_${widget.receiptId}',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: isNetwork
              ? Image.network(
                  imagePath,
                  height: 250,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _photoErrorPlaceholder(),
                )
              : (() {
                  String cleanBase64 = imagePath;
                  if (imagePath.contains(',')) {
                    cleanBase64 = imagePath.substring(imagePath.indexOf(',') + 1);
                  }
                  return Image.memory(
                    base64Decode(cleanBase64),
                    height: 250,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _photoErrorPlaceholder(),
                  );
                })(),
        ),
      ),
    );
  }

  Widget _photoErrorPlaceholder() {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.broken_image, size: 48, color: Colors.grey),
            SizedBox(height: 8),
            Text(AppStrings.cannotDisplayPhoto(_locale), style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  void _openFullscreenImage(BuildContext context, String imagePath) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(
            child: Hero(
              tag: 'receipt_image_${widget.receiptId}',
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: isNetworkImage(imagePath)
                    ? Image.network(imagePath, fit: BoxFit.contain)
                    : Image.memory(
                        base64Decode(extractBase64(imagePath)),
                        fit: BoxFit.contain,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool isNetworkImage(String path) => path.startsWith('http');

  String extractBase64(String imagePath) {
    if (imagePath.contains(',')) {
      return imagePath.substring(imagePath.indexOf(',') + 1);
    }
    return imagePath;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _transactionDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _transactionDate = picked);
  }

  Widget _buildItemCard(int index) {
    final item = _items[index];
    final itemName = item['item_name'] ?? '';
    final qty = (item['qty'] ?? 1).toDouble();
    final unitPrice = item['unit_price'];
    final prdCate = item['prd_cate'] ?? 'other';
    final lineTotal = item['line_total'] ?? (unitPrice != null ? (unitPrice * qty) : null);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    itemName,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${AppStrings.unitPrice(_locale)}: ${unitPrice != null ? 'HK\$$unitPrice' : '-'}  ×  $qty  =  ${lineTotal != null ? 'HK\$$lineTotal' : '-'}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _getPrdCateColor(prdCate).withAlpha(25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _getPrdCateName(prdCate),
                      style: TextStyle(fontSize: 11, color: _getPrdCateColor(prdCate)),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit, size: 20),
              onPressed: () => _showEditItemDialog(index),
              color: Colors.blue,
            ),
            IconButton(
              icon: const Icon(Icons.delete, size: 20),
              onPressed: () => _confirmDeleteItem(index),
              color: Colors.red,
            ),
          ],
        ),
      ),
    );
  }

  void _showEditItemDialog(int index) {
    final item = _items[index];
    final nameCtrl = TextEditingController(text: item['item_name']);
    final qtyCtrl = TextEditingController(text: (item['qty'] ?? 1).toString());
    final priceCtrl = TextEditingController(text: item['unit_price']?.toString() ?? '');
    String prdCate = item['prd_cate'] ?? 'other';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.editItem(_locale)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(labelText: AppStrings.itemName(_locale), border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: qtyCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: AppStrings.quantity(_locale), border: const OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: priceCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: AppStrings.unitPrice(_locale), border: const OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: prdCate,
                decoration: InputDecoration(labelText: '類別', border: OutlineInputBorder()),
                items: [
                  DropdownMenuItem(value: 'fish', child: Text(AppStrings.fish(_locale))),
                  DropdownMenuItem(value: 'pork', child: Text(AppStrings.pork(_locale))),
                  DropdownMenuItem(value: 'beef', child: Text(AppStrings.beef(_locale))),
                  DropdownMenuItem(value: 'chicken', child: Text(AppStrings.chicken(_locale))),
                  DropdownMenuItem(value: 'vegetables', child: Text(AppStrings.vegetables(_locale))),
                  DropdownMenuItem(value: 'rice', child: Text(AppStrings.rice(_locale))),
                  DropdownMenuItem(value: 'oil', child: Text(AppStrings.oil(_locale))),
                  DropdownMenuItem(value: 'seasoning', child: Text(AppStrings.seasoning(_locale))),
                  DropdownMenuItem(value: 'snack', child: Text(AppStrings.snack(_locale))),
                  DropdownMenuItem(value: 'drink', child: Text(AppStrings.drink(_locale))),
                  DropdownMenuItem(value: 'daily', child: Text(AppStrings.daily(_locale))),
                  DropdownMenuItem(value: 'takeaway', child: Text(AppStrings.takeaway(_locale))),
                  DropdownMenuItem(value: 'other', child: Text(AppStrings.otherStore(_locale))),
                ],
                onChanged: (v) => prdCate = v ?? 'other',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppStrings.cancel(_locale))),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              final qty = double.tryParse(qtyCtrl.text) ?? 1;
              final price = double.tryParse(priceCtrl.text);
              final lineTotal = price != null ? price * qty : null;
              _updateItem(index, {
                ...item,
                'item_name': nameCtrl.text.trim(),
                'qty': qty,
                'unit_price': price,
                'prd_cate': prdCate,
                'line_total': lineTotal,
              });
            },
            child: Text(AppStrings.save(_locale)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteItem(int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('🗑️ ${AppStrings.deleteItem(_locale)}'),
        content: Text('${AppStrings.confirmDelete(_locale)}「${_items[index]['item_name']}」？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppStrings.cancel(_locale))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              _deleteItem(index);
            },
            child: Text(AppStrings.delete(_locale)),
          ),
        ],
      ),
    );
  }

  Color _getPrdCateColor(String cate) {
    const map = {
      'fish': Colors.blue,
      'pork': Colors.red,
      'beef': Colors.brown,
      'chicken': Colors.orange,
      'vegetables': Colors.green,
      'rice': Colors.amber,
      'oil': Colors.yellow,
      'seasoning': Colors.purple,
      'snack': Colors.pink,
      'drink': Colors.cyan,
      'daily': Colors.teal,
      'takeaway': Colors.deepOrange,
    };
    return map[cate] ?? Colors.grey;
  }

  String _getPrdCateName(String cate) {
    final names = _prdCategories[cate];
    if (names == null) return cate;
    // Use name_en for English locale, name_tc for all others (TC, ID, FIL)
    return _locale == AppLocale.english ? (names['en'] ?? names['tc']!) : names['tc']!;
  }
}