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
  Map<String, dynamic>? _receipt;
  List<Map<String, dynamic>> _items = [];
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

      setState(() {
        _receipt = Map<String, dynamic>.from(receiptRes);
        _items = List<Map<String, dynamic>>.from(itemsRes as List);
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
          const SnackBar(content: Text('✅ 已儲存'), backgroundColor: Colors.green),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ 儲存失敗: $e'), backgroundColor: Colors.red),
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
          SnackBar(content: Text('❌ 更新失敗: $e'), backgroundColor: Colors.red),
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
      debugPrint('Delete result: $result');
      if (mounted) Navigator.pop(context, 'deleted');
    } catch (e) {
      debugPrint('Delete receipt error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('刪除失敗：$e')),
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
          SnackBar(content: Text('❌ 刪除失敗: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('收據詳情'),
        actions: [
          if (!_isLoading)
            TextButton.icon(
              onPressed: _isSaving ? null : _saveChanges,
              icon: _isSaving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: Text(_isSaving ? '儲存中…' : '儲存'),
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
                      _buildPhotoSection(),
                      const SizedBox(height: 24),
                      _buildSectionTitle('🏪 商戶資料'),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _storeNameController,
                        decoration: const InputDecoration(
                          labelText: '商戶名稱',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.store),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _storeCate,
                        decoration: const InputDecoration(
                          labelText: '商戶類別',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.category),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'supermarket', child: Text('超市')),
                          DropdownMenuItem(value: 'wet_market', child: Text('街市')),
                          DropdownMenuItem(value: 'pharmacy', child: Text('藥房')),
                          DropdownMenuItem(value: 'convenience', child: Text('便利店')),
                          DropdownMenuItem(value: 'online', child: Text('網購')),
                          DropdownMenuItem(value: 'restaurant', child: Text('餐廳')),
                          DropdownMenuItem(value: 'cafe', child: Text('茶餐廳')),
                          DropdownMenuItem(value: 'takeaway', child: Text('外賣')),
                          DropdownMenuItem(value: 'other', child: Text('其他')),
                        ],
                        onChanged: (v) => setState(() => _storeCate = v ?? 'other'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _locationController,
                        decoration: const InputDecoration(
                          labelText: '地址 / 地區',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.location_on),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _buildSectionTitle('💰 金額與日期'),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _amountController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: '總金額 (HK\$)',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.attach_money),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: InkWell(
                              onTap: _pickDate,
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: '消費日期',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.calendar_today),
                                ),
                                child: Text(
                                  _transactionDate != null
                                      ? '${_transactionDate!.year}-${_transactionDate!.month.toString().padLeft(2, '0')}-${_transactionDate!.day.toString().padLeft(2, '0')}'
                                      : '請選擇日期',
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _buildSectionTitle('🛒 項目明細'),
                      const SizedBox(height: 12),
                      if (_items.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Center(
                            child: Text('暫無項目', style: TextStyle(color: Colors.grey)),
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
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.receipt_long, size: 48, color: Colors.grey),
              SizedBox(height: 8),
              Text('沒有收據相片', style: TextStyle(color: Colors.grey)),
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
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.broken_image, size: 48, color: Colors.grey),
            SizedBox(height: 8),
            Text('無法顯示相片', style: TextStyle(color: Colors.grey)),
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
                    '單價: ${unitPrice != null ? 'HK\$$unitPrice' : '-'}  ×  $qty  =  ${lineTotal != null ? 'HK\$$lineTotal' : '-'}',
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
        title: const Text('✏️ 編輯項目'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: '項目名稱', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: qtyCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '數量', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: priceCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '單價 (HK\$)', border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: prdCate,
                decoration: const InputDecoration(labelText: '類別', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'fish', child: Text('魚')),
                  DropdownMenuItem(value: 'pork', child: Text('豬肉')),
                  DropdownMenuItem(value: 'beef', child: Text('牛肉')),
                  DropdownMenuItem(value: 'chicken', child: Text('雞')),
                  DropdownMenuItem(value: 'vegetables', child: Text('蔬菜')),
                  DropdownMenuItem(value: 'rice', child: Text('米')),
                  DropdownMenuItem(value: 'oil', child: Text('油')),
                  DropdownMenuItem(value: 'seasoning', child: Text('調味料')),
                  DropdownMenuItem(value: 'snack', child: Text('零食')),
                  DropdownMenuItem(value: 'drink', child: Text('飲料')),
                  DropdownMenuItem(value: 'daily', child: Text('日用品')),
                  DropdownMenuItem(value: 'takeaway', child: Text('外賣')),
                  DropdownMenuItem(value: 'other', child: Text('其他')),
                ],
                onChanged: (v) => prdCate = v ?? 'other',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
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
            child: const Text('儲存'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteItem(int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🗑️ 刪除項目？'),
        content: Text('確定要刪除「${_items[index]['item_name']}」？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              _deleteItem(index);
            },
            child: const Text('刪除'),
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
    const map = {
      'fish': '魚',
      'pork': '豬肉',
      'beef': '牛肉',
      'chicken': '雞',
      'vegetables': '蔬菜',
      'rice': '米',
      'oil': '油',
      'seasoning': '調味料',
      'snack': '零食',
      'drink': '飲料',
      'daily': '日用品',
      'takeaway': '外賣',
      'other': '其他',
    };
    return map[cate] ?? '其他';
  }
}