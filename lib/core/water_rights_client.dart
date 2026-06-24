import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:prior/data/water_right.dart';

// UGRC geocoding API — free key required, register at api.mapserv.utah.gov
// For now using a placeholder; user will need to register and add their key.
const _ugrcApiKey = 'UGRC-1635F681245929';

// UGRC PLSS layer — township/range/section boundaries
const _plssLayer =
    'https://services1.arcgis.com/99lidPhWCzftIe9K/arcgis/rest/services/PLSS_Fabric/FeatureServer/1';

// Utah DWRi Point of Diversion (POD) layer via UGRC Open SGID
// These are queryable by proximity/section
const _podLayer =
    'https://services1.arcgis.com/99lidPhWCzftIe9K/arcgis/rest/services/WaterRights_Points/FeatureServer/0';

class WaterRightsClient {
  WaterRightsClient._();
  static final instance = WaterRightsClient._();

  /// Full lookup: address → lat/lng → PLSS section → water rights near that point
  Future<LookupResult> lookupByAddress(String address) async {
    // Step 1: Geocode address to lat/lng via UGRC
    final coords = await _geocodeAddress(address);
    if (coords == null) {
      return LookupResult.error(
        'Could not find that address. Try including the city, e.g. "1234 Main St, St George UT"',
      );
    }

    return lookupByCoords(coords.$1, coords.$2, address: address);
  }

  /// Lookup by coordinates (from map tap)
  Future<LookupResult> lookupByCoords(
    double lat,
    double lng, {
    String? address,
  }) async {
    // Step 2: Find PLSS section at these coordinates
    final plss = await _plssAtPoint(lat, lng);

    // Step 3: Find water rights (points of diversion) near this location
    final rights = await _waterRightsNear(lat, lng);

    return LookupResult(
      lat: lat,
      lng: lng,
      address: address,
      plssDescription: plss,
      rights: rights,
    );
  }

  Future<(double, double)?> _geocodeAddress(String address) async {
    // UGRC single-address geocoder
    final encoded = Uri.encodeComponent(address);
    final uri = Uri.parse(
      'https://api.mapserv.utah.gov/api/v1/geocode/$encoded/utah?apiKey=$_ugrcApiKey&spatialReference=4326',
    );
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final result = json['result'] as Map<String, dynamic>?;
      if (result == null) return null;
      final loc = result['location'] as Map<String, dynamic>?;
      if (loc == null) return null;
      final x = (loc['x'] as num?)?.toDouble();
      final y = (loc['y'] as num?)?.toDouble();
      if (x == null || y == null) return null;
      debugPrint('Geocoded: $y, $x');
      return (y, x); // lat, lng
    } catch (e) {
      debugPrint('Geocode error: $e');
      return null;
    }
  }

  Future<String?> _plssAtPoint(double lat, double lng) async {
    final uri = Uri.parse('$_plssLayer/query').replace(
      queryParameters: {
        'geometry': '$lng,$lat',
        'geometryType': 'esriGeometryPoint',
        'spatialRel': 'esriSpatialRelIntersects',
        'inSR': '4326',
        'outFields': 'TWNSHPLAB,RANGEDIR,TWNSHPDIR,SECTIONLABEL,LABEL',
        'returnGeometry': 'false',
        'f': 'json',
      },
    );
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final features = json['features'] as List?;
      if (features == null || features.isEmpty) return null;
      final a =
          (features.first as Map<String, dynamic>)['attributes']
              as Map<String, dynamic>? ??
          {};
      debugPrint('PLSS attrs: $a');
      final label = a['LABEL'] ?? a['TWNSHPLAB'];
      return label?.toString();
    } catch (e) {
      debugPrint('PLSS error: $e');
      return null;
    }
  }

  Future<List<WaterRight>> _waterRightsNear(double lat, double lng) async {
    // Query water rights within ~1 mile radius (roughly 0.015 degrees)
    final uri = Uri.parse('$_podLayer/query').replace(
      queryParameters: {
        'geometry': '$lng,$lat',
        'geometryType': 'esriGeometryPoint',
        'spatialRel': 'esriSpatialRelIntersects',
        'inSR': '4326',
        'distance': '1609', // 1 mile in meters
        'units': 'esriSRUnit_Meter',
        'outFields': '*',
        'returnGeometry': 'true',
        'outSR': '4326',
        'f': 'json',
      },
    );
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return [];
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final features = json['features'] as List? ?? [];
      debugPrint('Water rights features: ${features.length}');
      return features.map((f) {
        final attrs =
            (f as Map<String, dynamic>)['attributes']
                as Map<String, dynamic>? ??
            {};
        final geom = f['geometry'] as Map<String, dynamic>?;
        if (geom != null) {
          attrs['LAT'] = geom['y'];
          attrs['LNG'] = geom['x'];
        }
        return WaterRight.fromArcGis(attrs);
      }).toList();
    } catch (e) {
      debugPrint('Water rights error: $e');
      return [];
    }
  }
}

class LookupResult {
  final double? lat;
  final double? lng;
  final String? address;
  final String? plssDescription;
  final List<WaterRight> rights;
  final String? errorMessage;

  const LookupResult({
    this.lat,
    this.lng,
    this.address,
    this.plssDescription,
    this.rights = const [],
    this.errorMessage,
  });

  const LookupResult.error(String message)
    : lat = null,
      lng = null,
      address = null,
      plssDescription = null,
      rights = const [],
      errorMessage = message;

  bool get hasError => errorMessage != null;
}
