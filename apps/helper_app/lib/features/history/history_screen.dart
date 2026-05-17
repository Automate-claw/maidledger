import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/supabase_client_provider.dart';
import 'receipt_detail_screen.dart';

/// History screen for viewing past receipts
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  List<Map<String, dynamic>> _receipts = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadReceipts();
  }

  Future<void> _loadReceipts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await supabase
          .from('receipts')
          .select()
          .order('created_at', ascending: false)
          .limit(50);

      final receipts = List<Map<String, dynamic>>.from(response as List);

      // Fetch items count per receipt
      if (receipts.isNotEmpty) {
        final ids = receipts.map((r) => r['id'] as String).toList();
        final itemsRes = await supabase
            .from('receipt_items')
            .select('id, receipt_id')
            .in_('receipt_id', ids);
        final itemsList = itemsRes as List;
        final itemsPerReceipt = <String, int>{};
        for (final item in itemsList) {
          final rid = item['receipt_id'] as String;
          itemsPerReceipt[rid] = (itemsPerReceipt[rid] ?? 0) + 1;
        }
        for (final r in receipts) {
          r['_items_count'] = itemsPerReceipt[r['id']] ?? 0;
        }
      }

      setState(() {
        _receipts = receipts;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteReceipt(String id) async {
    try {
      await supabase.from('receipts').delete().eq('id', id);

      setState(() {
        _receipts.removeWhere((r) => r['id'] == id);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🗑️ Receipt deleted'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Delete failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadReceipts,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 64, color: Colors.red),
                      const SizedBox(height: 16),
                      Text('Error: $_error'),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _loadReceipts,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _receipts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.receipt_long, size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            'No receipts yet',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Start scanning or chatting to add expenses',
                            style: TextStyle(color: Colors.grey[500]),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadReceipts,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _receipts.length,
                        itemBuilder: (context, index) {
                          final receipt = _receipts[index];
                          return ReceiptCard(
                            receipt: receipt,
                            onDelete: () => _deleteReceipt(receipt['id'] as String),
                            onTap: () async {
                              final changed = await Navigator.push<bool>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ReceiptDetailScreen(
                                    receiptId: receipt['id'] as String,
                                  ),
                                ),
                              );
                              if (changed == true) _loadReceipts();
                            },
                          );
                        },
                      ),
                    ),
    );
  }
}

class ReceiptCard extends StatelessWidget {
  final Map<String, dynamic> receipt;
  final VoidCallback onDelete;
  final VoidCallback? onTap;

  const ReceiptCard({
    super.key,
    required this.receipt,
    required this.onDelete,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final amount = receipt['amount'];
    final storeCate = receipt['store_cate'] as String? ?? 'other';
    final syncStatus = receipt['sync_status'] as String? ?? 'pending';
    final createdAt = DateTime.tryParse(receipt['created_at'] as String? ?? '');
    final storeName = receipt['store_name'] as String?;
    final itemsCount = receipt['_items_count'] as int? ?? 0;
    final hasImage = (receipt['image_local_path'] as String?)?.isNotEmpty == true;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Photo indicator or category icon
                  Container(
                    width: 48,
                    height: 48,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: hasImage
                          ? Colors.grey[200]
                          : _getCategoryColor(storeCate).withValues(alpha: 0.1),
                    ),
                    child: Icon(
                      hasImage ? Icons.receipt : _getCategoryIcon(storeCate),
                      color: hasImage ? Colors.grey : _getCategoryColor(storeCate),
                      size: 24,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              amount != null ? '\$${amount.toStringAsFixed(0)}' : '-',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (storeName != null && storeName.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  storeName,
                                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: _getCategoryColor(storeCate).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _getCategoryName(storeCate),
                                style: TextStyle(fontSize: 11, color: _getCategoryColor(storeCate)),
                              ),
                            ),
                            if (itemsCount > 0) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '$itemsCount 項',
                                  style: const TextStyle(fontSize: 11, color: Colors.blue),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  _buildSyncStatusChip(syncStatus),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (createdAt != null) ...[
                    Icon(Icons.access_time, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(
                      _formatDate(createdAt),
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                  ],
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () => _confirmDelete(context),
                    color: Colors.red[300],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSyncStatusChip(String status) {
    Color color;
    String label;
    IconData icon;

    switch (status) {
      case 'synced':
        color = Colors.green;
        label = 'Synced';
        icon = Icons.cloud_done;
        break;
      case 'pending':
        color = Colors.orange;
        label = 'Pending';
        icon = Icons.cloud_upload;
        break;
      case 'conflict':
        color = Colors.red;
        label = 'Conflict';
        icon = Icons.cloud_off;
        break;
      default:
        color = Colors.grey;
        label = status;
        icon = Icons.cloud_queue;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🗑️ Delete Receipt?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              onDelete();
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'supermarket':
        return Colors.blue;
      case 'wet_market':
        return Colors.green;
      case 'pharmacy':
        return Colors.red;
      case 'convenience':
        return Colors.orange;
      case 'online':
        return Colors.purple;
      case 'restaurant':
        return Colors.deepOrange;
      case 'cafe':
        return Colors.brown;
      case 'takeaway':
        return Colors.amber[700]!;
      default:
        return Colors.grey;
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'supermarket':
        return Icons.shopping_cart;
      case 'wet_market':
        return Icons.storefront;
      case 'pharmacy':
        return Icons.local_pharmacy;
      case 'convenience':
        return Icons.store;
      case 'online':
        return Icons.language;
      case 'restaurant':
        return Icons.restaurant;
      case 'cafe':
        return Icons.local_cafe;
      case 'takeaway':
        return Icons.takeout_dining;
      default:
        return Icons.receipt;
    }
  }

  String _getCategoryName(String category) {
    switch (category) {
      case 'supermarket':
        return '超市';
      case 'wet_market':
        return '街市';
      case 'pharmacy':
        return '藥房';
      case 'convenience':
        return '便利店';
      case 'online':
        return '網購';
      case 'restaurant':
        return '餐廳';
      case 'cafe':
        return '茶餐廳';
      case 'takeaway':
        return '外賣';
      default:
        return '其他';
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    return '${date.month}/${date.day} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}