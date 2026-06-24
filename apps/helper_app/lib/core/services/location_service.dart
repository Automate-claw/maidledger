import 'dart:convert';
import 'dart:io';

// GpsResult is defined in this file

class GpsResult {
  final double latitude;
  final double longitude;

  GpsResult({required this.latitude, required this.longitude});
}

class LocationResult {
  final String? region;   // 港島 / 九龍 / 新界
  final String? district; // 荃灣、筲箕灣、灣仔等
  final String? displayText;
  final double? confidence;

  LocationResult({
    this.region,
    this.district,
    this.displayText,
    this.confidence,
  });

  String get fallbackText {
    if (district != null) return district!;
    if (region != null) return region!;
    return "未知地點";
  }
}

class LocationService {
  /// Nominatim reverse geocode: GPS → district/region name
  /// Falls back to coordinate-based region if Nominatim fails or times out.
  Future<LocationResult?> reverseGeocode(GpsResult gps) async {
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?lat=${gps.latitude}&lon=${gps.longitude}'
        '&format=json&accept-language=zh-tw',
      );

      final httpClient = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
      final req = await httpClient.getUrl(uri);
      req.headers.set('User-Agent', 'MaidLedgerApp/1.0');
      final resp = await req.close();

      if (resp.statusCode != 200) {
        debugPrint('🔵 [reverseGeocode] non-200 status: ${resp.statusCode}, falling back to coordinates');
        // Nominatim failed (403/429/timeout/etc) → use coordinate-based fallback
        return _regionFallback(gps.latitude, gps.longitude);
      }

      final jsonStr = await resp
          .transform(utf8.decoder)
          .join();

      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final addr = json['address'] as Map<String, dynamic>?;

      if (addr == null) {
        return _regionFallback(gps.latitude, gps.longitude);
      }

      // Priority: city > town > village > suburb > county
      final district = addr['city']
          ?? addr['town']
          ?? addr['village']
          ?? addr['suburb']
          ?? addr['county'];

      final region = _inferRegion(district ?? '', addr);

      return LocationResult(
        region: region,
        district: district,
        displayText: district ?? region,
        confidence: 0.9,
      );
    } catch (e) {
      debugPrint('🔵 [reverseGeocode] error: $e, falling back to coordinates');
      return _regionFallback(gps.latitude, gps.longitude);
    }
  }

  String _inferRegion(String district, Map<String, dynamic> addr) {
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

    // Priority 3: unknown
    return '未知';
  }

  LocationResult _regionFallback(double lat, double lon) {
    // Rough fallback using coordinates only
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

  /// Extract location from EXIF bytes (photo GPS) — no network needed
  /// This is used when user sends a photo with embedded GPS
  LocationResult? reverseGeocodeLocal(GpsResult gps) {
    // No local DB needed, delegate to async Nominatim
    // This sync version just returns the coordinate-based fallback
    return _regionFallback(gps.latitude, gps.longitude);
  }
}