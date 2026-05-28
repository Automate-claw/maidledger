import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Weight option data
class WeightOption {
  final int weightG;
  final String label;
  final String unitType; // 'g', 'pcs', 'kg'

  WeightOption({required this.weightG, required this.label, required this.unitType});
}

/// Provider to fetch weight options for a subcategory
final weightOptionsProvider = FutureProvider.family<List<WeightOption>, String?>((ref, subcategoryCode) async {
  if (subcategoryCode == null) return [];
  final client = Supabase.instance.client;
  final resp = await client
      .from('weight_options')
      .select('weight_g, label, unit_type')
      .eq('subcategory_code', subcategoryCode)
      .order('display_order', ascending: true);
  return (resp as List)
      .map((r) => WeightOption(weightG: r['weight_g'] as int, label: r['label'] as String, unitType: r['unit_type'] as String))
      .toList();
});

/// Weight option chip selector widget
class WeightOptionChipSelector extends ConsumerWidget {
  final String? subcategoryCode;
  final int? selectedWeightG;
  final ValueChanged<int?> onSelected;

  const WeightOptionChipSelector({
    super.key,
    required this.subcategoryCode,
    required this.selectedWeightG,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (subcategoryCode == null) return const SizedBox.shrink();

    final asyncOpts = ref.watch(weightOptionsProvider(subcategoryCode));

    return asyncOpts.when(
      data: (opts) {
        if (opts.isEmpty) return const SizedBox.shrink();
        return Wrap(
          spacing: 6,
          runSpacing: 4,
          children: opts.map((opt) {
            final isSelected = selectedWeightG != null && opt.weightG == selectedWeightG;
            return ChoiceChip(
              label: Text(opt.label, style: const TextStyle(fontSize: 12)),
              selected: isSelected,
              onSelected: (selected) {
                onSelected(selected ? opt.weightG : null);
              },
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 4),
            );
          }).toList(),
        );
      },
      loading: () => const SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
