import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:maidledger_localization/maidledger_localization.dart';
import '../../core/services/supabase_client_provider.dart';
import '../auth/auth_provider.dart';

/// Provider for current relation (employer-helper link)
final currentRelationProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;

  final supabase = ref.read(supabaseClientProvider);
  final relations = await supabase
      .from('employer_helper_relations')
      .select('id, helper_id, status')
      .eq('employer_id', user.id)
      .eq('status', 'active')
      .maybeSingle();
  return relations;
});

/// Provider for employer payments for current relation
final employerPaymentsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];

  final supabase = ref.read(supabaseClientProvider);
  final payments = await supabase
      .from('employer_payments')
      .select('id, amount, payment_date, note, helper_id, created_at')
      .eq('employer_id', user.id)
      .order('payment_date', ascending: false);
  return (payments as List).cast<Map<String, dynamic>>();
});

/// Provider for receipts between two payment dates
final receiptsBetweenPaymentsProvider = FutureProvider.family<List<Map<String, dynamic>>, _PeriodQuery>((ref, query) async {
  final supabase = ref.read(supabaseClientProvider);
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
      .eq('helper_id', query.helperId)
      .gte('transaction_date', query.startDate)
      .lt('transaction_date', query.endDate)
      .order('transaction_date', ascending: false);
  return (receipts as List).cast<Map<String, dynamic>>();
});

/// Query parameters for receipts between payments
class _PeriodQuery {
  final String helperId;
  final String startDate; // payment date (inclusive)
  final String endDate;   // next payment date or 'now'

  _PeriodQuery({required this.helperId, required this.startDate, required this.endDate});

  @override
  bool operator ==(Object other) =>
      other is _PeriodQuery &&
      other.helperId == helperId &&
      other.startDate == other.startDate &&
      other.endDate == other.endDate;

  @override
  int get hashCode => Object.hash(helperId, startDate, endDate);
}

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

/// Provider for employer's receipts (all, for display)
final employerReceiptsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];

  final supabase = ref.read(supabaseClientProvider);
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

class ReceiptsScreen extends ConsumerWidget {
  const ReceiptsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final paymentsAsync = ref.watch(employerPaymentsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.receipts(locale)),
        centerTitle: true,
      ),
      body: paymentsAsync.when(
        data: (payments) {
          if (payments.isEmpty) {
            return _EmptyState(locale: locale);
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(employerPaymentsProvider);
              ref.invalidate(employerReceiptsProvider);
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _BalanceCard(locale: locale),
                const SizedBox(height: 16),
                _PaymentsSection(payments: payments, locale: locale),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('${AppStrings.loadingFailed(locale)}: $err')),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final AppLocale locale;
  const _EmptyState({required this.locale});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.receipt_long, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            AppStrings.noReceipts(locale),
            style: const TextStyle(color: Colors.grey, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            AppStrings.noReceiptsHint(locale),
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _BalanceCard extends ConsumerWidget {
  final AppLocale locale;
  const _BalanceCard({required this.locale});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paymentsAsync = ref.watch(employerPaymentsProvider);

    return paymentsAsync.when(
      data: (payments) {
        final income = payments.fold<double>(0, (sum, p) => sum + ((p['amount'] as num?)?.toDouble() ?? 0));
        return _BalanceCardContent(income: income, locale: locale);
      },
      loading: () => const Card(
        child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
      ),
      error: (_, __) => const SizedBox(),
    );
  }
}

class _BalanceCardContent extends ConsumerStatefulWidget {
  final double income;
  final AppLocale locale;

  const _BalanceCardContent({required this.income, required this.locale});

  @override
  ConsumerState<_BalanceCardContent> createState() => _BalanceCardContentState();
}

class _BalanceCardContentState extends ConsumerState<_BalanceCardContent> {
  double _computedExpense = 0;
  bool _expenseLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadExpense());
  }

  Future<void> _loadExpense() async {
    final relation = await ref.read(currentRelationProvider.future);
    if (relation == null) return;
    if (!mounted) return;

    final supabase = ref.read(supabaseClientProvider);
    final receipts = await supabase
        .from('receipts')
        .select('amount')
        .eq('helper_id', relation['helper_id']);
    final expense = (receipts as List).fold<double>(0, (sum, r) => sum + ((r['amount'] as num?)?.toDouble() ?? 0));
    if (mounted) {
      setState(() {
        _computedExpense = expense;
        _expenseLoaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final balance = widget.income - _computedExpense;
    final isPositive = balance >= 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isPositive ? [Colors.green[700]!, Colors.green[500]!] : [Colors.red[700]!, Colors.red[500]!],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: (isPositive ? Colors.green : Colors.red).withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.cashBalance(widget.locale),
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            '\$${balance.abs().toStringAsFixed(0)}',
            style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold),
          ),
          if (!isPositive)
            Text(AppStrings.overdraft(widget.locale), style: const TextStyle(color: Colors.white60, fontSize: 12)),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildBalanceRow(AppStrings.received(widget.locale), widget.income, Icons.arrow_downward),
              const SizedBox(width: 24),
              _buildBalanceRow(AppStrings.spent(widget.locale), _computedExpense, Icons.arrow_upward),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceRow(String label, double amount, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 14),
        const SizedBox(width: 4),
        Text(
          '$label \$${amount.toStringAsFixed(0)}',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}

class _PaymentsSection extends StatelessWidget {
  final List<Map<String, dynamic>> payments;
  final AppLocale locale;

  const _PaymentsSection({required this.payments, required this.locale});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppStrings.payments(locale),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ...payments.asMap().entries.map((entry) {
          final index = entry.key;
          final payment = entry.value;
          final isLast = index == payments.length - 1;
          return _PaymentTile(
            payment: payment,
            nextPaymentDate: isLast ? null : payments[index + 1]['payment_date'] as String?,
            locale: locale,
          );
        }),
      ],
    );
  }
}

class _PaymentTile extends StatefulWidget {
  final Map<String, dynamic> payment;
  final String? nextPaymentDate;
  final AppLocale locale;

  const _PaymentTile({
    required this.payment,
    this.nextPaymentDate,
    required this.locale,
  });

  @override
  State<_PaymentTile> createState() => _PaymentTileState();
}

class _PaymentTileState extends State<_PaymentTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final amount = (widget.payment['amount'] as num?)?.toDouble() ?? 0;
    final paymentDate = widget.payment['payment_date'] as String?;
    final dateStr = paymentDate != null ? DateFormat('yyyy-MM-dd').format(DateTime.parse(paymentDate)) : '-';
    final endDate = widget.nextPaymentDate ?? DateFormat('yyyy-MM-dd').format(DateTime.now().add(const Duration(days: 1)));

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.arrow_downward, color: Colors.green, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppStrings.fromPayment(widget.locale, dateStr),
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        if (widget.nextPaymentDate == null)
                          const Text('至現在', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  ),
                  Text(
                    '+\$${amount.toStringAsFixed(0)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green),
                  ),
                  const SizedBox(width: 8),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more, color: Colors.grey),
                ],
              ),
            ),
          ),
          if (_expanded)
            _PeriodReceipts(
              helperId: widget.payment['helper_id'] as String,
              startDate: paymentDate!,
              endDate: endDate,
              locale: widget.locale,
            ),
        ],
      ),
    );
  }
}

class _PeriodReceipts extends ConsumerWidget {
  final String helperId;
  final String startDate;
  final String endDate;
  final AppLocale locale;

  const _PeriodReceipts({
    required this.helperId,
    required this.startDate,
    required this.endDate,
    required this.locale,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receiptsAsync = ref.watch(receiptsBetweenPaymentsProvider(
      _PeriodQuery(helperId: helperId, startDate: startDate, endDate: endDate),
    ));

    return receiptsAsync.when(
      data: (receipts) {
        if (receipts.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(AppStrings.noReceiptsHint(locale), style: const TextStyle(color: Colors.grey, fontSize: 13)),
          );
        }
        return Column(
          children: [
            const Divider(height: 1),
            ...receipts.map((r) => _PeriodReceiptTile(receipt: r, locale: locale)),
          ],
        );
      },
      loading: () => const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
      error: (_, __) => Padding(padding: const EdgeInsets.all(16), child: Text(AppStrings.loadingFailed(locale), style: const TextStyle(color: Colors.red, fontSize: 13))),
    );
  }
}

class _PeriodReceiptTile extends StatelessWidget {
  final Map<String, dynamic> receipt;
  final AppLocale locale;

  const _PeriodReceiptTile({required this.receipt, required this.locale});

  @override
  Widget build(BuildContext context) {
    final storeName = receipt['store_name'] ?? '未知商戶';
    final amount = (receipt['amount'] as num?)?.toDouble() ?? 0;
    final transactionDate = receipt['transaction_date'] as String?;
    final dateStr = transactionDate != null ? DateFormat('MM-dd').format(DateTime.parse(transactionDate)) : '-';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(dateStr, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(width: 12),
          Expanded(child: Text(storeName, style: const TextStyle(fontSize: 14))),
          Text('\$${amount.toStringAsFixed(0)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

/// Provider for receipt items
final _receiptItemsProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, receiptId) async {
  final supabase = ref.read(supabaseClientProvider);
  final items = await supabase.from('receipt_items').select().eq('receipt_id', receiptId);
  return (items as List).cast<Map<String, dynamic>>();
});
