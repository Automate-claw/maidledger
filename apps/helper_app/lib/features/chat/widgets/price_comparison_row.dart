import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// CC price comparison data for an item
class CcPriceComparison {
  final String ccCode;
  final String ccName;
  final int standardWeightG;
  final double pricePer100g;
  final Map<String, double> storePrices; // { "WELLCOME": 54.90 }

  CcPriceComparison({
    required this.ccCode,
    required this.ccName,
    required this.standardWeightG,
    required this.pricePer100g,
    required this.storePrices,
  });
}

/// Provider to find CC price match for an item
final ccPriceMatchProvider = FutureProvider.family<CcPriceComparison?, String?>((ref, masterProductId) async {
  if (masterProductId == null) return null;
  final client = Supabase.instance.client;

  // Get master_product with cc_code
  final mp = await client
      .from('master_products')
      .select('cc_code, name_en, name_zh')
      .eq('id', masterProductId)
      .maybeSingle();
  if (mp == null || mp['cc_code'] == null) return null;

  final ccCode = mp['cc_code'] as String;

  // Get CC price
  final cc = await client
      .from('cc_prices')
      .select('cc_code, name_zh, standard_weight_g, price_per_100g, prices')
      .eq('cc_code', ccCode)
      .maybeSingle();
  if (cc == null) return null;

  return CcPriceComparison(
    ccCode: cc['cc_code'] as String,
    ccName: (cc['name_zh'] ?? cc['name_en'] ?? '') as String,
    standardWeightG: cc['standard_weight_g'] as int? ?? 0,
    pricePer100g: (cc['price_per_100g'] as num?)?.toDouble() ?? 0,
    storePrices: (cc['prices'] is Map) ? Map<String, double>.fromEntries(
      (cc['prices'] as Map).entries.map((e) => MapEntry(e.key.toString(), (e.value as num).toDouble()))
    ) : {},
  );
});

/// Price comparison row widget
class PriceComparisonRow extends ConsumerWidget {
  final int itemIndex;
  final String itemName;
  final String? masterProductId;
  final double? actualPrice; // total price paid
  final int? selectedWeightG;
  final String? subcategoryCode;

  const PriceComparisonRow({
    super.key,
    required this.itemIndex,
    required this.itemName,
    required this.masterProductId,
    required this.actualPrice,
    required this.selectedWeightG,
    required this.subcategoryCode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (masterProductId == null || actualPrice == null || selectedWeightG == null) {
      return const SizedBox.shrink();
    }

    final asyncCc = ref.watch(ccPriceMatchProvider(masterProductId));

    return asyncCc.when(
      data: (cc) {
        if (cc == null) return const SizedBox.shrink();

        final actualPer100g = selectedWeightG! > 0
            ? (actualPrice! / selectedWeightG! * 100 * 100).toStringAsFixed(1)
            : '-';
        final ccPer100g = cc.pricePer100g.toStringAsFixed(2);
        final diff = selectedWeightG! > 0
            ? ((actualPrice! / selectedWeightG! * 100) - cc.pricePer100g) * 100
            : 0.0;
        final diffPct = cc.pricePer100g > 0
            ? (diff / cc.pricePer100g * 100).toStringAsFixed(0)
            : '0';

        final isCheaper = diff < 0;
        final diffIcon = isCheaper ? '📉' : '📈';
        final diffColor = isCheaper ? Colors.green : Colors.red;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: diffColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: diffColor.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Text('$diffIcon ', style: TextStyle(fontSize: 14)),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                    children: [
                      const TextSpan(text: '你的: '),
                      TextSpan(text: 'HK\$$actualPrice/${selectedWeightG}g', style: const TextStyle(fontWeight: FontWeight.w600)),
                      TextSpan(text: ' = $actualPer100g/100g', style: const TextStyle(color: Colors.grey)),
                      const TextSpan(text: ' | '),
                      const TextSpan(text: '🏪 CC: ', style: TextStyle(color: Colors.grey[600])),
                      TextSpan(text: '$ccPer100g/100g', style: TextStyle(color: diffColor, fontWeight: FontWeight.w600)),
                      const TextSpan(text: ' ', style: TextStyle(color: Colors.grey)),
                      const TextSpan(text: '差額: '),
                      TextSpan(text: '${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(2)}/100g ', style: TextStyle(color: diffColor)),
                      TextSpan(text: '($diffPct%)', style: TextStyle(color: diffColor, fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox(
        height: 16,
        width: 16,
        child: CircularProgressIndicator(strokeWidth: 1.5),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
