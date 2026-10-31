import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:prior/core/states/state_outlines.dart';
import 'package:prior/core/states/state_source.dart';
import 'package:prior/data/water_right.dart';

/// Idaho: IDWR's points of diversion for licensed and decreed rights
/// (gis.idwr.idaho.gov Allocation/WaterRightPods). Idaho has no free
/// statewide parcel layer, so results are by distance from the point
/// rather than by parcel.
class IdahoSource extends StateSource {
  const IdahoSource();

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
            '${_describe(radius)} of this spot, nearest first. Idaho has no '
            'free statewide parcel map yet, so check the place of use on '
            'the IDWR report.',
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
