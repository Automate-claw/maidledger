import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:maidledger_localization/maidledger_localization.dart';
import '../../core/services/supabase_client_provider.dart';
import 'receipt_detail_screen.dart';
import 'record_payment_screen.dart';

/// History screen with calendar view + rolling balance
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  AppLocale get _locale => ref.watch(localeProvider);
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  Map<DateTime, List<ReceiptDayItem>> _receiptsByDay = {};
  List<PaymentRecord> _payments = [];
  bool _isLoading = true;
  String? _error;
  double _totalIncome = 0;
  double _totalExpense = 0;
  double _balance = 0;


  Future<void> _shareDailySummary() async {
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final response = await supabase.functions.invoke('daily-summary');

      Navigator.pop(context);

      if (response.data == null || response.data['text'] == null) {
        if (mounted) {
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('錯誤：$e')),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() { _isLoading = true; _error = null; });

    try {
      final userId = supabase.auth.currentSession?.user.id;
      if (userId == null) throw Exception('Not logged in');

      // Load ALL receipts for this helper (not just filtered by relation)
      // This ensures we show receipts even if relation_id is null or different
      final receiptsRes = await supabase
          .from('receipts')
          .select('id, amount, transaction_date, created_at, store_name, store_cate, parse_status, relation_id, date_anomaly')
          .eq('helper_id', userId)
          .order('transaction_date', ascending: false);

      final receipts = List<Map<String, dynamic>>.from(receiptsRes as List);

      // Get active relation for balance calculation
      final relations = await supabase
          .from('employer_helper_relations')
          .select('id, employer_id')
          .eq('helper_id', userId)
          .eq('status', 'active')
          .maybeSingle();
      final relationId = relations?['id'] as String?;
      final employerId = relations?['employer_id'] as String?;

      // Load payments (load ALL for this helper — relation_id may be null for unlinked helpers)
      List<PaymentRecord> payments = [];
      double totalIncome = 0;
      final paymentsRes = await supabase
          .from('employer_payments')
          .select('id, amount, payment_date, note, employer_id, created_by')
          .eq('helper_id', userId)
          .order('payment_date', ascending: false);
      final paymentsList = List<Map<String, dynamic>>.from(paymentsRes as List);
      for (final p in paymentsList) {
        final amount = (p['amount'] as num).toDouble();
        totalIncome += amount;
        final isRecordedByHelper = p['created_by'] == userId;
        payments.add(PaymentRecord(
          id: p['id'] as String,
          amount: amount,
          date: DateTime.parse(p['payment_date'] as String),
          note: p['note'] as String?,
          isEmployer: p['employer_id'] == employerId,
          recordedByHelper: isRecordedByHelper,
        ));
      }

      // Group receipts by day
      final byDay = <DateTime, List<ReceiptDayItem>>{};
      double totalExpense = 0;
      for (final r in receipts) {
        final dateStr = r['transaction_date'] as String? ?? (r['created_at'] as String).split('T')[0];
        if (dateStr == null) continue;
        final date = DateTime.parse(dateStr);
        final dayKey = DateTime(date.year, date.month, date.day);
        final amount = (r['amount'] as num?)?.toDouble() ?? 0;
        totalExpense += amount;
        byDay.putIfAbsent(dayKey, () => []).add(ReceiptDayItem(
          id: r['id'] as String,
          amount: amount,
          storeName: r['store_name'] as String?,
          storeCate: r['store_cate'] as String? ?? 'other',
          createdAt: date,
          dateAnomaly: r['date_anomaly'] as bool? ?? false,
        ));
      }

      // Compute balance via SQL
      final incomeRes = await supabase
          .from('employer_payments')
          .select('amount')
          .eq('helper_id', userId);
      final expenseRes = await supabase
          .from('receipts')
          .select('amount')
          .eq('helper_id', userId);
      final income = (incomeRes as List)
          .fold<double>(0, (sum, r) => sum + ((r['amount'] as num?)?.toDouble() ?? 0));
      final expense = (expenseRes as List)
          .fold<double>(0, (sum, r) => sum + ((r['amount'] as num?)?.toDouble() ?? 0));
      _balance = income - expense;

      setState(() {
        _payments = payments;
        _receiptsByDay = byDay;
        _totalIncome = totalIncome;
        _totalExpense = totalExpense;
        _isLoading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  bool get _isPositiveBalance => _balance >= 0;

  List<ReceiptDayItem> _getReceiptsForDay(DateTime day) {
    final key = DateTime(day.year, day.month, day.day);
    return _receiptsByDay[key] ?? [];
  }

  List<PaymentRecord> _getPaymentsForDay(DateTime day) {
    return _payments.where((p) =>
      p.date.year == day.year &&
      p.date.month == day.month &&
      p.date.day == day.day
    ).toList();
  }

  double _getCumulativeBalanceUpTo(DateTime day) {
    // Calculate balance up to (and including) the given day
    double income = 0;
    double expense = 0;
    for (final p in _payments) {
      if (p.date.isBefore(day) || p.date.isAtSameMomentAs(day)) {
        income += p.amount;
      }
    }
    for (final entry in _receiptsByDay.entries) {
      final dayKey = entry.key;
      if (dayKey.isBefore(day) || dayKey.isAtSameMomentAs(day)) {
        for (final r in entry.value) expense += r.amount;
      }
    }
    return income - expense;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.historyTitle(_locale)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: '分享今日摘要',
            onPressed: _shareDailySummary,
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: AppStrings.recentRecords(_locale),
            onPressed: () => _showRecentRecords(context),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('${AppStrings.error(_locale)}: $_error'))
              : Column(
                  children: [
                    _buildBalanceCard(),
                    _buildCalendar(),
                    const Divider(height: 1),
                    Expanded(child: _buildDayDetail()),
                  ],
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showRecordPayment(context),
        child: const Icon(Icons.add_card),
        tooltip: 'Record Payment',
      ),
    );
  }

  Widget _buildBalanceCard() {
    final balanceColor = _isPositiveBalance ? Colors.green : Colors.red;
    final balanceLabel = _balance >= 0 ? AppStrings.balance(_locale) : AppStrings.overdraft(_locale);

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _isPositiveBalance
              ? [Colors.green[700]!, Colors.green[500]!]
              : [Colors.red[700]!, Colors.red[500]!],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: (balanceColor).withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppStrings.cashBalance(_locale), style: const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                  '\$${_balance.abs().toStringAsFixed(0)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (!_isPositiveBalance)
                  Text(AppStrings.overdraft(_locale), style: const TextStyle(color: Colors.white60, fontSize: 12)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildBalanceRow(AppStrings.received(_locale), _totalIncome, Icons.arrow_downward),
              const SizedBox(height: 4),
              _buildBalanceRow(AppStrings.spent(_locale), _totalExpense, Icons.arrow_upward),
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

  Widget _buildCalendar() {
    return TableCalendar(
      firstDay: DateTime(2020, 1, 1),
      lastDay: DateTime.now().add(const Duration(days: 30)),
      focusedDay: _focusedDay,
      calendarFormat: _calendarFormat,
      selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
      onDaySelected: (selectedDay, focusedDay) {
        setState(() {
          _selectedDay = selectedDay;
          _focusedDay = focusedDay;
        });
      },
      onFormatChanged: (format) {
        setState(() { _calendarFormat = format; });
      },
      onPageChanged: (focusedDay) {
        _focusedDay = focusedDay;
      },
      calendarBuilders: CalendarBuilders(
        markerBuilder: (context, date, events) {
          final receipts = _getReceiptsForDay(date);
          final payments = _getPaymentsForDay(date);
          if (receipts.isEmpty && payments.isEmpty) return null;

          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (payments.isNotEmpty)
                Container(
                  width: 6, height: 6,
                  decoration: const BoxDecoration(
                    color: Colors.green, shape: BoxShape.circle,
                  ),
                ),
              if (payments.isNotEmpty && receipts.isNotEmpty) const SizedBox(width: 2),
              if (receipts.isNotEmpty)
                Container(
                  width: 6, height: 6,
                  decoration: BoxDecoration(
                    color: receipts.any((r) => r.dateAnomaly)
                        ? Colors.orange
                        : Colors.red[400],
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          );
        },
      ),
      calendarStyle: CalendarStyle(
        todayDecoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.3),
          shape: BoxShape.circle,
        ),
        selectedDecoration: const BoxDecoration(
          color: Colors.blue,
          shape: BoxShape.circle,
        ),
        markerSize: 8,
        markersMaxCount: 2,
      ),
      headerStyle: const HeaderStyle(
        formatButtonVisible: true,
        titleCentered: true,
      ),
    );
  }

  Widget _buildDayDetail() {
    final day = _selectedDay ?? DateTime.now();
    final receipts = _getReceiptsForDay(day);
    final payments = _getPaymentsForDay(day);
    final dayBalance = _getCumulativeBalanceUpTo(day);

    if (receipts.isEmpty && payments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_available, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              '${DateFormat('MMM d').format(day)} — No records',
              style: TextStyle(color: Colors.grey[500]),
            ),
            const SizedBox(height: 4),
            Text(
              'Tap + to record a payment',
              style: TextStyle(color: Colors.grey[400], fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // Day summary
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Text(
                DateFormat('EEEE, MMM d').format(day),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: dayBalance >= 0 ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Balance: \$${dayBalance.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: dayBalance >= 0 ? Colors.green[700] : Colors.red[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Payments first
        ...payments.map((p) => _buildPaymentTile(p)),
        // Then receipts
        ...receipts.map((r) => _buildReceiptTile(r)),
      ],
    );
  }

  Widget _buildPaymentTile(PaymentRecord p) {
    final recordedBy = p.recordedByHelper ? '你' : '僱主';
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: Colors.amber.withValues(alpha: 0.08),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.amber[100],
          child: Icon(Icons.payments, color: Colors.amber[700], size: 20),
        ),
        title: Text(
          '+\$${p.amount.toStringAsFixed(0)}',
          style: TextStyle(color: Colors.amber[800], fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Text(
          p.note ?? (p.isEmployer ? '僱主付款 ($recordedBy 記錄)' : 'Payment recorded'),
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              DateFormat('HH:mm').format(p.date),
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
            Text(
              recordedBy,
              style: TextStyle(fontSize: 10, color: Colors.grey[400]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReceiptTile(ReceiptDayItem r) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.red.withValues(alpha: 0.1),
          child: const Icon(Icons.receipt, color: Colors.red, size: 20),
        ),
        title: Text(
          '-\$${r.amount.toStringAsFixed(0)}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Text(r.storeName ?? _getCategoryName(r.storeCate)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.access_time, size: 12, color: Colors.grey[400]),
            const SizedBox(width: 4),
            Text(
              DateFormat('HH:mm').format(r.createdAt),
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, color: Colors.grey[400], size: 20),
          ],
        ),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ReceiptDetailScreen(receiptId: r.id),
            ),
          );
          _loadData();
        },
      ),
    );
  }

  void _showRecordPayment(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RecordPaymentScreen()),
    ).then((_) => _loadData());
  }

  void _showRecentRecords(BuildContext context) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final userId = user.id;

    // Fetch recent receipts
    final receiptsRes = await supabase
        .from('receipts')
        .select('id, amount, transaction_date, store_name, date_anomaly, created_at')
        .eq('helper_id', userId)
        .order('created_at', ascending: false)
        .limit(10);

    // Fetch recent payments
    final paymentsRes = await supabase
        .from('employer_payments')
        .select('id, amount, payment_date, created_at, created_by')
        .eq('helper_id', userId)
        .order('created_at', ascending: false)
        .limit(10);

    final receipts = List<Map<String, dynamic>>.from(receiptsRes as List);
    final payments = List<Map<String, dynamic>>.from(paymentsRes as List);

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.history, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    AppStrings.recentRecords(_locale),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: scrollController,
                children: [
                  // Payments section
                  if (payments.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(
                        '💰 ${AppStrings.cashBalance(_locale)}',
                        style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w500),
                      ),
                    ),
                    ...payments.map((p) {
                      final recordedBy = p['created_by'] == userId ? '你' : '僱主';
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.add_circle, color: Colors.green, size: 20),
                        title: Text('+\$${(p['amount'] as num).toStringAsFixed(2)}'),
                        subtitle: Text('${p['payment_date'] ?? p['created_at']} ($recordedBy 記錄)'),
                      );
                    }),
                  ],
                  // Receipts section
                  if (receipts.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(
                        '🧾 Receipts',
                        style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w500),
                      ),
                    ),
                    ...receipts.map((r) {
                      final isAnomaly = r['date_anomaly'] as bool? ?? false;
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.receipt,
                          color: isAnomaly ? Colors.orange : Colors.red[400],
                          size: 20,
                        ),
                        title: Row(
                          children: [
                            Text('- \$${(r['amount'] as num?)?.toStringAsFixed(2) ?? '0.00'}'),
                            if (isAnomaly) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.orange[100],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('⚠️', style: TextStyle(fontSize: 10)),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text('${r['store_name'] ?? '未知商戶'} — ${r['transaction_date'] ?? r['created_at']}'),
                        onTap: () {
                          Navigator.pop(ctx);
                          // Navigate to receipt detail
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ReceiptDetailScreen(receiptId: r['id'] as String),
                            ),
                          );
                        },
                      );
                    }),
                  ],
                  if (receipts.isEmpty && payments.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Text(
                          AppStrings.noItems(_locale),
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getCategoryName(String category) {
    const names = {
      'supermarket': '超市',
      'wet_market': '街市',
      'pharmacy': '藥房',
      'convenience': '便利店',
      'online': '網購',
      'restaurant': '餐廳',
      'cafe': '茶餐廳',
      'takeaway': '外賣',
    };
    return names[category] ?? '其他';
  }
}

class ReceiptDayItem {
  final String id;
  final double amount;
  final String? storeName;
  final String storeCate;
  final DateTime createdAt;
  final bool dateAnomaly;

  ReceiptDayItem({
    required this.id,
    required this.amount,
    this.storeName,
    required this.storeCate,
    required this.createdAt,
    this.dateAnomaly = false,
  });
}

class PaymentRecord {
  final String id;
  final double amount;
  final DateTime date;
  final String? note;
  final bool isEmployer;
  final bool recordedByHelper; // true = helper recorded it, false = employer recorded it

  PaymentRecord({
    required this.id,
    required this.amount,
    required this.date,
    this.note,
    required this.isEmployer,
    required this.recordedByHelper,
  });
}