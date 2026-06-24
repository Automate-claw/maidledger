import 'package:flutter_test/flutter_test.dart';
import 'package:maidledger/core/services/location_service.dart';

void main() {
  group('LocationService', () {
    group('GpsResult', () {
      test('stores latitude and longitude', () {
        final gps = GpsResult(latitude: 22.3193, longitude: 114.1694);
        expect(gps.latitude, equals(22.3193));
        expect(gps.longitude, equals(114.1694));
      });

      test('handles extreme coordinates', () {
        final gps = GpsResult(latitude: 90.0, longitude: 180.0);
        expect(gps.latitude, equals(90.0));
        expect(gps.longitude, equals(180.0));
      });
    });

    group('LocationResult', () {
      test('stores all location fields', () {
        final result = LocationResult(
          region: '九龍',
          district: '旺角',
          displayText: '旺角',
          confidence: 0.9,
        );

        expect(result.region, equals('九龍'));
        expect(result.district, equals('旺角'));
        expect(result.displayText, equals('旺角'));
        expect(result.confidence, equals(0.9));
      });

      test('fallbackText returns district when available', () {
        final result = LocationResult(
          region: '九龍',
          district: '旺角',
        );
        expect(result.fallbackText, equals('旺角'));
      });

      test('fallbackText returns region when district is null', () {
        final result = LocationResult(
          region: '新界',
          district: null,
        );
        expect(result.fallbackText, equals('新界'));
      });

      test('fallbackText returns unknown when both are null', () {
        final result = LocationResult();
        expect(result.fallbackText, equals('未知地點'));
      });

      test('handles empty strings', () {
        final result = LocationResult(
          region: '',
          district: '',
        );
        expect(result.fallbackText, equals(''));
      });

      test('nullable confidence', () {
        final result = LocationResult(confidence: null);
        expect(result.confidence, isNull);
      });
    });

    group('_inferRegion', () {
      late LocationService service;

      setUp(() {
        service = LocationService();
      });

      // District name inference (Priority 1)
      test('detects 港島 from district 筲箕灣 (Shau Kei Wan)', () {
        final result = _inferRegionForTest('筲箕灣', {});
        expect(result, equals('港島'));
      });

      test('detects 港島 from district 柴灣', () {
        final result = _inferRegionForTest('柴灣', {});
        expect(result, equals('港島'));
      });

      test('detects 港島 from district 銅鑼灣', () {
        final result = _inferRegionForTest('銅鑼灣', {});
        expect(result, equals('港島'));
      });

      test('detects 港島 from district 北角', () {
        final result = _inferRegionForTest('北角', {});
        expect(result, equals('港島'));
      });

      test('detects 港島 from district 中西區', () {
        final result = _inferRegionForTest('中西區', {});
        expect(result, equals('港島'));
      });

      test('detects 九龍 from district 旺角', () {
        final result = _inferRegionForTest('旺角', {});
        expect(result, equals('九龍'));
      });

      test('detects 九龍 from district 油尖旺', () {
        final result = _inferRegionForTest('油尖旺', {});
        expect(result, equals('九龍'));
      });

      test('detects 新界 from district 荃灣', () {
        final result = _inferRegionForTest('荃灣', {});
        expect(result, equals('新界'));
      });

      test('detects 新界 from district 將軍澳', () {
        final result = _inferRegionForTest('將軍澳', {});
        expect(result, equals('新界'));
      });

      // Nominatim region field (Priority 2)
      test('detects 港島 from region name', () {
        final result = _inferRegionForTest('', {'region': '香港島'});
        expect(result, equals('港島'));
      });

      test('detects 九龍 from region name', () {
        final result = _inferRegionForTest('', {'region': '九龍城'});
        expect(result, equals('九龍'));
      });

      test('detects New Territories from region name', () {
        final result = _inferRegionForTest('', {'region': '新界區'});
        expect(result, equals('新界'));
      });

      test('returns unknown for unrecognized region', () {
        final result = _inferRegionForTest('', {'region': '其他'});
        expect(result, equals('未知'));
      });

      test('handles null region', () {
        final result = _inferRegionForTest('', {});
        expect(result, equals('未知'));
      });

      // District name takes priority over region field
      test('district name takes priority over Nominatim region field', () {
        // Shau Kei Wan Nominatim sometimes returns region='九龍' due to admin boundaries
        final result = _inferRegionForTest('筲箕灣', {'region': '九龍'});
        expect(result, equals('港島'));
      });
    });

    group('_regionFallback (coordinate-based)', () {
      late LocationService service;

      setUp(() {
        service = LocationService();
      });

      test('returns New Territories for lat > 22.36', () {
        final result = _regionFallbackForTest(22.5, 114.0);
        expect(result.region, equals('新界'));
        expect(result.confidence, equals(0.3));
      });

      test('returns Kowloon for lat between 22.29 and 22.36', () {
        final result = _regionFallbackForTest(22.32, 114.0);
        expect(result.region, equals('九龍'));
        expect(result.confidence, equals(0.3));
      });

      test('returns Hong Kong Island for lat <= 22.29', () {
        final result = _regionFallbackForTest(22.28, 114.0);
        expect(result.region, equals('港島'));
        expect(result.confidence, equals(0.3));
      });

      test('boundary case: exactly 22.36 returns 九龍 (not strictly greater)', () {
        // lat > 22.36 is false when lat == 22.36, so it falls to lat > 22.29 -> 九龍
        final result = _regionFallbackForTest(22.36, 114.0);
        expect(result.region, equals('九龍'));
      });

      test('boundary case: exactly 22.29 returns 港島 (not strictly greater)', () {
        // lat > 22.29 is false when lat == 22.29, so it falls to else -> 港島
        final result = _regionFallbackForTest(22.29, 114.0);
        expect(result.region, equals('港島'));
      });

      test('boundary case: just above 22.36 returns 新界', () {
        final result = _regionFallbackForTest(22.37, 114.0);
        expect(result.region, equals('新界'));
      });
    });
  });
}

/// Test helpers that mirror private implementation for unit testing
/// MUST stay in sync with LocationService._inferRegion
String _inferRegionForTest(String district, Map<String, dynamic> addr) {
  // Priority 1: infer from district name (most reliable for HK)
  if (district.isNotEmpty) {
    if (district.contains('港島') || district.contains('香港島') ||
        district.contains('中西') || district.contains('灣仔') ||
        district.contains('東區') || district.contains('南區') ||
        district.contains('筲箕') || district.contains('柴灣') ||
        district.contains('西環') || district.contains('上環') ||
        district.contains('下環') || district.contains('堅尼') ||
        district.contains('銅鑼灣') || district.contains('北角') ||
        district.contains('天后') || district.contains('炮台山')) {
      return '港島';
    }
    if (district.contains('九龍') || district.contains('油尖') ||
        district.contains('旺角') || district.contains('深水') ||
        district.contains('九龍城') || district.contains('黃大仙') ||
        district.contains('觀塘') || district.contains('鯉魚門') ||
        district.contains('秀茂坪') || district.contains('牛頭角') ||
        district.contains('佐敦') || district.contains('土瓜灣') ||
        district.contains('何文田') || district.contains('紅磡') ||
        district.contains('筆架山') || district.contains('九龍塘')) {
      return '九龍';
    }
    if (district.contains('新界') || district.contains('荃灣') ||
        district.contains('葵涌') || district.contains('荔景') ||
        district.contains('青山') || district.contains('屯門') ||
        district.contains('元朗') || district.contains('天水') ||
        district.contains('粉嶺') || district.contains('上水') ||
        district.contains('大埔') || district.contains('沙田') ||
        district.contains('馬鞍山') || district.contains('將軍澳') ||
        district.contains('西貢') || district.contains('清水') ||
        district.contains('東涌') || district.contains('大嶼山') ||
        district.contains('愉景') || district.contains('梅窩') ||
        district.contains('長洲') || district.contains('南丫島')) {
      return '新界';
    }
  }

  // Priority 2: use addr['region'] from Nominatim (less reliable)
  final region = addr['region'] as String?;
  if (region != null) {
    if (region.contains('港島') || region.contains('香港島')) return '港島';
    if (region.contains('九龍')) return '九龍';
    if (region.contains('新界')) return '新界';
  }

  return '未知';
}

LocationResult _regionFallbackForTest(double lat, double lon) {
  String region;
  if (lat > 22.36) {
    region = '新界';
  } else if (lat > 22.29) {
    region = '九龍';
  } else {
    region = '港島';
  }
  return LocationResult(region: region, confidence: 0.3);
}