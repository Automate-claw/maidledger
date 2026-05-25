import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:maidledger_localization/maidledger_localization.dart';
import '../../core/services/supabase_client_provider.dart';

/// Screen to record a payment received (from employer or self)
class RecordPaymentScreen extends ConsumerStatefulWidget {
  const RecordPaymentScreen({super.key});

  @override
  ConsumerState<RecordPaymentScreen> createState() => _RecordPaymentScreenState();
}

class _RecordPaymentScreenState extends ConsumerState<RecordPaymentScreen> {
  AppLocale get _locale => ref.watch(localeProvider);

  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  DateTime _paymentDate = DateTime.now();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paymentDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() { _paymentDate = picked; });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      setState(() { _error = AppStrings.enterValidAmount(_locale); });
      return;
    }

    setState(() { _isLoading = true; _error = null; });

    try {
      final userId = supabase.auth.currentSession?.user.id;
      if (userId == null) throw Exception('Not logged in');

      String? relationId;
      String? employerId;

      // Try to find active relation (optional — helper can record even without one)
      final relations = await supabase
          .from('employer_helper_relations')
          .select('id, employer_id')
          .eq('helper_id', userId)
          .eq('status', 'active')
          .maybeSingle();
      relationId = relations?['id'] as String?;
      employerId = relations?['employer_id'] as String?;

      // Insert payment — relation_id / employer_id can be null for unlinked helpers
      // RLS policy allows helper to insert with just helper_id
      await supabase.from('employer_payments').insert({
        'relation_id': relationId,
        'employer_id': employerId,
        'helper_id': userId,
        'amount': amount,
        'payment_date': DateFormat('yyyy-MM-dd', _locale.code).format(_paymentDate),
        'note': _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
        'created_by': userId,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.paymentSaved(_locale)),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() { _error = '${AppStrings.paymentFailed(_locale)}: $e'; _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.recordPayment(_locale)),
        centerTitle: true,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Amount
            TextFormField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: AppStrings.amount(_locale),
                prefixText: '\$ ',
                prefixStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.green.withValues(alpha: 0.05),
              ),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              validator: (v) {
                final n = double.tryParse(v ?? '');
                if (n == null || n <= 0) return AppStrings.enterValidAmount(_locale);
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Date
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey[300]!),
              ),
              leading: const Icon(Icons.calendar_today),
              title: Text(AppStrings.date(_locale)),
              subtitle: Text(DateFormat.yMd(_locale.code).format(_paymentDate)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _selectDate,
            ),
            const SizedBox(height: 16),

            // Note
            TextFormField(
              controller: _noteController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: AppStrings.note(_locale),
                hintText: AppStrings.noteHint(_locale),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.grey.withValues(alpha: 0.05),
              ),
            ),
            const SizedBox(height: 8),

            // Error
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),

            const SizedBox(height: 24),

            // Quick amount buttons
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final amt in [500, 1000, 2000, 3000, 5000])
                  ActionChip(
                    label: Text('\$$amt'),
                    onPressed: () => _amountController.text = amt.toString(),
                  ),
              ],
            ),
            const SizedBox(height: 32),

            // Save button
            FilledButton.icon(
              onPressed: _isLoading ? null : _save,
              icon: _isLoading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: Text(AppStrings.savePayment(_locale)),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.green,
              ),
            ),
          ],
        ),
      ),
    );
  }
}