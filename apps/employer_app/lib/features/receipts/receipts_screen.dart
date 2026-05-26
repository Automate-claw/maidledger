import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/services/supabase_client_provider.dart';
import '../auth/auth_provider.dart';

/// Provider for employer's receipts
final employerReceiptsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];

  final supabase = ref.read(supabaseClientProvider);
  
  // Get receipts where employer_id matches current user
  final receipts = await supabase
      .from('receipts')
      .select('''
        id,
        store_name,
        store_cate,
        location,
        amount,
        transaction_date,
        raw_text,
        image_local_path,
        sync_status,
        created_at,
        helper_id
      ''')
      .eq('employer_id', user.id)
      .order('created_at', ascending: false)
      .limit(100);

  return (receipts as List).cast<Map<String, dynamic>>();
});

/// Provider for helper name (helper_id → name)
final helperNamesProvider = FutureProvider.family<String?, String>((ref, helperId) async {
  final supabase = ref.read(supabaseClientProvider);
  final profile = await supabase
      .from('user_profiles')
      .select('name')
      .eq('id', helperId)
      .maybeSingle();
  return profile?['name'] as String?;
});

class ReceiptsScreen extends ConsumerWidget {
  const ReceiptsScreen({super.key});

  void _shareDailySummary(BuildContext context, WidgetRef ref) async {
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final supabase = ref.read(supabaseClientProvider);
      final user = ref.read(currentUserProvider);
      if (user == null) {
        Navigator.pop(context);
        return;
      }

      final response = await supabase.functions.invoke('daily-summary');

      Navigator.pop(context);

      if (response.data == null || response.data['text'] == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('無法獲取摘要')),
          );
        }
        return;
      }

      final text = response.data['text'] as String;

      // Use share_plus to open system share sheet
      await Share.share(text);

    } catch (e) {
      Navigator.pop(context);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('錯誤：$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receiptsAsync = ref.watch(employerReceiptsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('收據列表'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: '分享今日摘要',
            onPressed: () => _shareDailySummary(context, ref),
          ),
        ],
      ),
      body: receiptsAsync.when(
        data: (receipts) {
          if (receipts.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.receipt_long, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    '暫時沒有收據',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '工人上傳後會在這裡顯示',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => ref.refresh(employerReceiptsProvider.future),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: receipts.length,
              itemBuilder: (context, index) {
                final receipt = receipts[index];
                return _ReceiptCard(receipt: receipt);
              },
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('載入失敗：$err')),
      ),
    );
  }
}

class _ReceiptCard extends ConsumerWidget {
  final Map<String, dynamic> receipt;

  const _ReceiptCard({required this.receipt});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storeName = receipt['store_name'] ?? '未知商戶';
    final storeCate = receipt['store_cate'] ?? 'other';
    final amount = receipt['amount'];
    final transactionDate = receipt['transaction_date'];
    final imageUrl = receipt['image_local_path'];
    final syncStatus = receipt['sync_status'] ?? 'pending';

    final helperNameAsync = ref.watch(helperNamesProvider(receipt['helper_id'] ?? ''));

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _showReceiptDetail(context, receipt),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  _buildCategoryIcon(storeCate),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          storeName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        if (transactionDate != null)
                          Text(
                            DateFormat('yyyy-MM-dd').format(
                              DateTime.parse(transactionDate),
                            ),
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (amount != null)
                    Text(
                      '\$${(amount as num).toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                        color: Colors.green,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              // Footer row
              Row(
                children: [
                  helperNameAsync.when(
                    data: (name) => Text(
                      name != null ? '工人：$name' : '',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    loading: () => const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1)),
                    error: (_, __) => const SizedBox(),
                  ),
                  const Spacer(),
                  _buildStatusChip(syncStatus),
                  if (imageUrl != null)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.photo, size: 16, color: Colors.grey),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryIcon(String cate) {
    IconData icon;
    Color color;

    switch (cate) {
      case 'supermarket':
        icon = Icons.shopping_cart;
        color = Colors.blue;
        break;
      case 'wet_market':
        icon = Icons.storefront;
        color = Colors.orange;
        break;
      case 'pharmacy':
        icon = Icons.local_pharmacy;
        color = Colors.red;
        break;
      case 'cafe':
      case 'restaurant':
        icon = Icons.restaurant;
        color = Colors.purple;
        break;
      case 'takeaway':
        icon = Icons.takeout_dining;
        color = Colors.brown;
        break;
      default:
        icon = Icons.receipt;
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color, size: 24),
    );
  }

  Widget _buildStatusChip(String status) {
    Color color;
    String label;

    switch (status) {
      case 'synced':
        color = Colors.green;
        label = '已同步';
        break;
      case 'pending':
        color = Colors.orange;
        label = '待確認';
        break;
      default:
        color = Colors.grey;
        label = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: color),
      ),
    );
  }

  void _showReceiptDetail(BuildContext context, Map<String, dynamic> receipt) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _ReceiptDetailSheet(receipt: receipt),
    );
  }
}

class _ReceiptDetailSheet extends ConsumerWidget {
  final Map<String, dynamic> receipt;

  const _ReceiptDetailSheet({required this.receipt});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imageUrl = receipt['image_local_path'];
    final rawText = receipt['raw_text'] ?? '';
    final itemsAsync = ref.watch(_receiptItemsProvider(receipt['id']));

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Title
              Row(
                children: [
                  const Icon(Icons.receipt, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      receipt['store_name'] ?? '未知商戶',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    '\$${(receipt['amount'] as num?)?.toStringAsFixed(0) ?? '-'}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Image if available
              if (imageUrl != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    imageUrl,
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              // Info chips
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    avatar: const Icon(Icons.category, size: 16),
                    label: Text(receipt['store_cate'] ?? 'other'),
                  ),
                  if (receipt['location'] != null)
                    Chip(
                      avatar: const Icon(Icons.location_on, size: 16),
                      label: Text(receipt['location']!),
                    ),
                  if (receipt['transaction_date'] != null)
                    Chip(
                      avatar: const Icon(Icons.calendar_today, size: 16),
                      label: Text(receipt['transaction_date']!),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              // Items
              const Text(
                '項目',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              itemsAsync.when(
                data: (items) {
                  if (items.isEmpty) {
                    return const Text('無項目資料', style: TextStyle(color: Colors.grey));
                  }
                  return Column(
                    children: items.map((item) => _ItemRow(item: item)).toList(),
                  );
                },
                loading: () => const CircularProgressIndicator(),
                error: (_, __) => const Text('無法載入項目'),
              ),
              const SizedBox(height: 16),
              // Raw OCR text
              const Text(
                'OCR 原文',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  rawText,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ItemRow extends StatelessWidget {
  final Map<String, dynamic> item;

  const _ItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              item['item_name'] ?? '',
              style: const TextStyle(fontSize: 14),
            ),
          ),
          if (item['unit_price'] != null)
            Text(
              '\$${(item['unit_price'] as num).toStringAsFixed(0)}',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
        ],
      ),
    );
  }
}

/// Provider for receipt items
final _receiptItemsProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, receiptId) async {
  final supabase = ref.read(supabaseClientProvider);
  final items = await supabase
      .from('receipt_items')
      .select()
      .eq('receipt_id', receiptId);
  return (items as List).cast<Map<String, dynamic>>();
});