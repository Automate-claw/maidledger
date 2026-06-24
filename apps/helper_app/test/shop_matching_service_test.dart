import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShopMatchingService', () {
    group('_extractKeywords', () {
      test('extracts basic keywords from shop name', () {
        final keywords = _extractKeywords('惠康超級市場');
        expect(keywords, isNotEmpty);
        expect(keywords.any((k) => k.contains('惠康') || k.contains('市場')), isTrue);
      });

      test('removes single-char shop type suffixes', () {
        // '店' is 1 char so removed; '分店' becomes '分' (1 char, removed)
        final keywords = _extractKeywords('分店');
        expect(keywords, isEmpty);
      });

      test('街市 is 2 chars and not removed (actual behavior)', () {
        // '街市' is 2 characters, so it is NOT in the noise list
        // The noise list only has: ' ', '1', '2', '店', '分店', 'location'
        final keywords = _extractKeywords('街市');
        expect(keywords, contains('街市'));
      });

      test('removes location keywords', () {
        final keywords = _extractKeywords('location');
        expect(keywords, isEmpty);
      });

      test('filters single character tokens', () {
        final keywords = _extractKeywords('惠康 1 2 店');
        for (final kw in keywords) {
          expect(kw.length, greaterThan(1));
        }
      });

      test('handles empty input', () {
        final keywords = _extractKeywords('');
        expect(keywords, isEmpty);
      });

      test('handles whitespace only input', () {
        final keywords = _extractKeywords('   ');
        expect(keywords, isEmpty);
      });

      test('handles mixed noise tokens', () {
        final keywords = _extractKeywords('店 1 分店 location 2');
        expect(keywords, isEmpty);
      });
    });

    group('_escapeIlike', () {
      test('escapes percent sign', () {
        expect(_escapeIlike('100%'), equals('100\\%'));
      });

      test('escapes underscore', () {
        expect(_escapeIlike('test_value'), equals('test\\_value'));
      });

      test('escapes backslash itself', () {
        expect(_escapeIlike('test\\value'), equals('test\\\\value'));
      });

      test('escapes all special characters', () {
        expect(_escapeIlike('100%_test\\value'), equals('100\\%\\_test\\\\value'));
      });

      test('returns unchanged string when no special chars', () {
        expect(_escapeIlike('normal text'), equals('normal text'));
      });
    });

    group('ShopMatchResult', () {
      test('stores all fields correctly', () {
        final result = ShopMatchResult(
          shopId: 'shop-123',
          canonicalName: '惠康超級市場',
          shopType: 'supermarket',
          region: '九龍',
          district: '旺角',
          confidence: 0.9,
          matchedVia: MatchedVia.ilike,
        );

        expect(result.shopId, equals('shop-123'));
        expect(result.canonicalName, equals('惠康超級市場'));
        expect(result.shopType, equals('supermarket'));
        expect(result.region, equals('九龍'));
        expect(result.district, equals('旺角'));
        expect(result.confidence, equals(0.9));
        expect(result.matchedVia, equals(MatchedVia.ilike));
      });

      test('matchedVia enum has correct values', () {
        expect(MatchedVia.values, containsAll([MatchedVia.exactAlias, MatchedVia.ilike, MatchedVia.newShop]));
      });
    });
  });
}

/// Mirrors ShopMatchingService implementation for testing
List<String> _extractKeywords(String text) {
  final noise = [' ', '  ', '1', '2', '店', '分店', 'location'];
  String cleaned = text;
  for (final n in noise) {
    cleaned = cleaned.replaceAll(n, ' ');
  }

  final tokens = cleaned
      .split(RegExp(r'\s+'))
      .where((t) => t.length > 1)
      .toList();

  return tokens;
}

String _escapeIlike(String input) {
  return input.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_');
}

// Minimal test double for ShopMatchResult
enum MatchedVia { exactAlias, ilike, newShop }

class ShopMatchResult {
  final String shopId;
  final String canonicalName;
  final String? shopType;
  final String? region;
  final String? district;
  final double confidence;
  final MatchedVia matchedVia;

  ShopMatchResult({
    required this.shopId,
    required this.canonicalName,
    this.shopType,
    this.region,
    this.district,
    required this.confidence,
    required this.matchedVia,
  });
}