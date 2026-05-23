import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
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
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  Map<DateTime, List<ReceiptDayItem>> _receiptsByDay = {};
  List<PaymentRecord> _payments = [];
  bool _isLoading = true;
  String? _error;
  double _totalIncome = 0;
  double _totalExpense = 0;

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
      final cutoff = DateTime.now().subtract(const Duration(days: 365));
      final receiptsRes = await supabase
          .from('receipts')
          .select('id, amount, created_at, store_name, store_cate, parse_status, relation_id')
          .eq('helper_id', userId)
          .gte('created_at', cutoff.toIso8601String())
          .order('created_at', ascending: false);

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

      // Load payments (only for active relation)
      List<PaymentRecord> payments = [];
      double totalIncome = 0;
      if (relationId != null) {
        final paymentsRes = await supabase
            .from('employer_payments')
            .select('id, amount, payment_date, note, employer_id')
            .eq('relation_id', relationId)
            .order('payment_date', ascending: false);
        final paymentsList = List<Map<String, dynamic>>.from(paymentsRes as List);
        for (final p in paymentsList) {
          final amount = (p['amount'] as num).toDouble();
          totalIncome += amount;
          payments.add(PaymentRecord(
            id: p['id'] as String,
            amount: amount,
            date: DateTime.parse(p['payment_date'] as String),
            note: p['note'] as String?,
            isEmployer: p['employer_id'] == employerId,
          ));
        }
      }

      // Group receipts by day
      final byDay = <DateTime, List<ReceiptDayItem>>{};
      double totalExpense = 0;
      for (final r in receipts) {
        final dateStr = r['created_at'] as String;
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
        ));
      }

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

  double get _balance => _totalIncome - _totalExpense;
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
        title: const Text('History'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
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
    final balanceLabel = _balance >= 0 ? 'Balance' : 'Overdraft';

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
                const Text('Cash Balance', style: TextStyle(color: Colors.white70, fontSize: 13)),
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
                  const Text('overdraft', style: TextStyle(color: Colors.white60, fontSize: 12)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildBalanceRow('Received', _totalIncome, Icons.arrow_downward),
              const SizedBox(height: 4),
              _buildBalanceRow('Spent', _totalExpense, Icons.arrow_upward),
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
      firstDay: DateTime.now().subtract(const Duration(days: 365)),
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
                    color: Colors.amber, shape: BoxShape.circle,
                  ),
                ),
              if (payments.isNotEmpty && receipts.isNotEmpty) const SizedBox(width: 2),
              if (receipts.isNotEmpty)
                Container(
                  width: 6, height: 6,
                  decoration: BoxDecoration(
                    color: Colors.red[400], shape: BoxShape.circle,
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
          p.note ?? (p.isEmployer ? 'Employer payment' : 'Payment recorded'),
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Text(
          DateFormat('HH:mm').format(p.date),
          style: TextStyle(color: Colors.grey[500], fontSize: 12),
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
          final changed = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (_) => ReceiptDetailScreen(receiptId: r.id),
            ),
          );
          if (changed == true) _loadData();
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

  ReceiptDayItem({
    required this.id,
    required this.amount,
    this.storeName,
    required this.storeCate,
    required this.createdAt,
  });
}

class PaymentRecord {
  final String id;
  final double amount;
  final DateTime date;
  final String? note;
  final bool isEmployer;

  PaymentRecord({
    required this.id,
    required this.amount,
    required this.date,
    this.note,
    required this.isEmployer,
  });
}