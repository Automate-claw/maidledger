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
  /// Returns null on failure (network error, rate limit, etc.)
  Future<LocationResult?> reverseGeocode(GpsResult gps) async {
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?lat=${gps.latitude}&lon=${gps.longitude}'
        '&format=json&accept-language=zh-tw',
      );

      final httpClient = HttpClient();
      final req = await httpClient.getUrl(uri);
      req.headers.set('User-Agent', 'MaidLedgerApp/1.0');
      final resp = await req.close();

      if (resp.statusCode != 200) {
        return null;
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
      return _regionFallback(gps.latitude, gps.longitude);
    }
  }

  String _inferRegion(String district, Map<String, dynamic> addr) {
    // Handle missing city/town by inferring from lat or addr
    final region = addr['region'] as String?;

    if (region != null) {
      if (region.contains('港島') || region.contains('香港島')) return '港島';
      if (region.contains('九龍')) return '九龍';
      if (region.contains('新界')) return '新界';
    }

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