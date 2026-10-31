import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:prior/core/states/state_outlines.dart';
import 'package:prior/core/states/state_source.dart';
import 'package:prior/core/water_rights_client.dart' show ParcelInfo;
import 'package:prior/data/water_right.dart';

/// Idaho: IDWR's points of diversion for licensed and decreed rights
/// (gis.idwr.idaho.gov Allocation/WaterRightPods), found by distance from
/// the point, plus the parcel there from IDWR's statewide parcel layer.
class IdahoSource extends StateSource {
  const IdahoSource();

  /// IDWR's compilation of county assessor parcels (outline, PIN, county).
  static const _parcelUrl =
      'https://gis.idwr.idaho.gov/hosting/rest/services/Reference/Parcels/FeatureServer/0';

  /// Idaho ITS public parcels: address, acres and value, for the counties
  /// that publish them.
  static const _publicParcelUrl =
      'https://services1.arcgis.com/CNPdEkvnGl65jCX8/arcgis/rest/services/Public_Idaho_Parcels_/FeatureServer/7';

  static const _podUrl =
      'https://gis.idwr.idaho.gov/hosting/rest/services/Allocation/WaterRightPods/FeatureServer/0';

  /// Search radii in meters, widened until something turns up. Points of
  /// diversion are sparse away from farms (in town, water usually comes
  /// from a city or irrigation company), so a tight radius often finds none.
  static const searchRadii = [250, 800, 1600];

  @override
  String get code => 'ID';

  @override
  String get name => 'Idaho';

  @override
  bool contains(double lat, double lng) => inState('ID', lat, lng);

  @override
  String get officialSearchUrl =>
      'https://research.idwr.idaho.gov/apps/shared/WrExtSearch/';

  @override
  Future<({List<WaterRight> rights, String? note})> waterRightsNear(
    double lat,
    double lng,
  ) async {
    for (final radius in searchRadii) {
      final rights = await _query(lat, lng, radius);
      if (rights == null) {
        return (
          rights: const <WaterRight>[],
          note: "Couldn't reach Idaho's water rights service. Try again.",
        );
      }
      if (rights.isEmpty) continue;
      rights.sort(
        (a, b) => _distance(lat, lng, a).compareTo(_distance(lat, lng, b)),
      );
      return (
        rights: rights.take(50).toList(),
        note:
            'Idaho: rights with a point of diversion within '
            '${_describe(radius)} of this spot, nearest first. A right can '
            "serve land away from where it's diverted, so check the place "
            'of use on the IDWR report.',
      );
    }
    return (
      rights: const <WaterRight>[],
      note:
          'Idaho: no water rights within ${_describe(searchRadii.last)}. '
          'In town, water usually comes from a city or irrigation company.',
    );
  }

  static String _describe(int meters) => meters >= 1600
      ? '1 mile'
      : meters >= 800
      ? '½ mile'
      : '$meters m';

  @override
  Future<ParcelInfo?> parcelAt(double lat, double lng) async {
    final results = await Future.wait([
      _attributesAt(_parcelUrl, lat, lng, 'PIN,COUNTY'),
      _attributesAt(
        _publicParcelUrl,
        lat,
        lng,
        'PARCEL_ID,County,SITE_ADD,SITE_CITY,SITE_ZIP,ASR_ACRES,VAL_TOTAL,'
        'ASR_CATS,WEBSITE',
      ),
    ]);
    final base = results[0];
    final extra = results[1];
    if (base == null && extra == null) return null;
    String? s(Map<String, dynamic>? m, String k) {
      final v = m?[k]?.toString().trim();
      return v == null || v.isEmpty || v == 'null' ? null : v;
    }

    return ParcelInfo(
      parcelId: s(extra, 'PARCEL_ID') ?? s(base, 'PIN') ?? '',
      address: s(extra, 'SITE_ADD'),
      city: s(extra, 'SITE_CITY'),
      zip: s(extra, 'SITE_ZIP'),
      county: s(extra, 'County') ?? s(base, 'COUNTY'),
      state: 'ID',
      countyUrl: s(extra, 'WEBSITE'),
      acres: (extra?['ASR_ACRES'] as num?)?.toDouble(),
      marketValue: (extra?['VAL_TOTAL'] as num?)?.toDouble(),
      propClass: s(extra, 'ASR_CATS'),
    );
  }

  /// The first feature's attributes at a point, or null.
  static Future<Map<String, dynamic>?> _attributesAt(
    String url,
    double lat,
    double lng,
    String fields,
  ) async {
    final uri = Uri.parse('$url/query').replace(
      queryParameters: {
        'geometry': '$lng,$lat',
        'geometryType': 'esriGeometryPoint',
        'spatialRel': 'esriSpatialRelIntersects',
        'inSR': '4326',
        'outFields': fields,
        'returnGeometry': 'false',
        'f': 'json',
      },
    );
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final features =
          (jsonDecode(res.body) as Map<String, dynamic>)['features'] as List?;
      if (features == null || features.isEmpty) return null;
      return Map<String, dynamic>.from(
        (features.first as Map)['attributes'] as Map,
      );
    } catch (e) {
      debugPrint('Idaho parcel error: $e');
      return null;
    }
  }

  /// Rough meters to the point of diversion (fine for sorting nearby).
  static double _distance(double lat, double lng, WaterRight r) {
    if (r.podLat == null || r.podLng == null) return double.infinity;
    final dLat = (r.podLat! - lat) * 111320;
    final dLng = (r.podLng! - lng) * 111320 * math.cos(lat * math.pi / 180);
    return math.sqrt(dLat * dLat + dLng * dLng);
  }

  /// Rights within [radius] m, or null if the service didn't answer.
  Future<List<WaterRight>?> _query(double lat, double lng, int radius) async {
    final uri = Uri.parse('$_podUrl/query').replace(
      queryParameters: {
        'where': '1=1',
        'geometry': '$lng,$lat',
        'geometryType': 'esriGeometryPoint',
        'spatialRel': 'esriSpatialRelIntersects',
        'inSR': '4326',
        'distance': '$radius',
        'units': 'esriSRUnit_Meter',
        'outFields': '*',
        'returnGeometry': 'true',
        'outSR': '4326',
        'resultRecordCount': '200',
        'f': 'json',
      },
    );
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      if (json['error'] != null) return null;
      final features = json['features'] as List? ?? [];
      final seen = <String>{};
      return [
        for (final f in features.cast<Map<String, dynamic>>())
          if (fromIdwr(f) case final r when seen.add(r.rightNumber)) r,
      ];
    } catch (e) {
      debugPrint('Idaho water rights error: $e');
      return null;
    }
  }

  /// One IDWR point-of-diversion feature as a [WaterRight].
  @visibleForTesting
  static WaterRight fromIdwr(Map<String, dynamic> feature) {
    final a = Map<String, dynamic>.from(
      feature['attributes'] as Map? ?? const {},
    );
    final geom = feature['geometry'] as Map<String, dynamic>?;
    String? s(String k) {
      final v = a[k]?.toString().trim();
      return v == null || v.isEmpty || v == 'null' ? null : v;
    }

    final priorityMs = (a['PriorityDate'] as num?)?.toInt();
    final source = s('Source');
    return WaterRight(
      rightNumber: s('WaterRightNumber') ?? '',
      source: [source, s('TributaryOf')].whereType<String>().join(', trib. '),
      sourceType: source == null
          ? null
          : source.toUpperCase().contains('GROUND')
          ? 'Underground'
          : 'Surface',
      priorityDate: priorityMs == null
          ? null
          : DateFormat('MM/dd/yyyy').format(
              DateTime.fromMillisecondsSinceEpoch(priorityMs, isUtc: true),
            ),
      cfs: (a['OverallMaxDiversionRate'] as num?)?.toDouble(),
      volumeAcreFt: (a['OverallMaxDiversionVolume'] as num?)?.toDouble(),
      beneficialUse: _titleCase(s('Uses')),
      status: [s('Status'), s('Basis')].whereType<String>().join(' · '),
      ownerName: s('Owner'),
      podLat: (geom?['y'] as num?)?.toDouble(),
      podLng: (geom?['x'] as num?)?.toDouble(),
      divisionOfWaterRightsUrl: s('WRReport'),
      raw: a,
    );
  }

  static String? _titleCase(String? v) => v
      ?.toLowerCase()
      .split(RegExp(r'\s*,\s*'))
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(', ');
}
