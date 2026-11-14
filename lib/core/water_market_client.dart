import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Utah water rights by area, for buyers and sellers rather than parcels:
/// "who holds water in this valley" and "is this right worth buying".
///
/// Utah numbers every right `area-serial` (73-1234). The area is the
/// hydrologic area the right sits in, and a right can generally only be moved
/// within its area, through a change application to the State Engineer. So
/// the area is the market.
const _podUrl =
    'https://services.arcgis.com/ZzrwjTRez6FJiOq4/ArcGIS/rest/services/Utah_Points_of_Diversion/FeatureServer/0';

const _outFields =
    'WRNUM,SUMMARY_ST,STATUS,TYPE_OF_RIGHT,TYPE,PRIORITY,USES,CFS,ACFT,OWNER,SOURCE,WebLink';

const _pageSize = 2000;

/// One water right, merged from its points of diversion (a right with three
/// wells has three rows in the state layer, each repeating its totals).
class AreaRight {
  const AreaRight({
    required this.number,
    required this.area,
    required this.owner,
    required this.summary,
    required this.status,
    required this.typeOfRight,
    required this.uses,
    required this.underground,
    required this.podCount,
    this.priority,
    this.acreFeet,
    this.cfs,
    this.source,
    this.lat,
    this.lng,
    this.webLink,
  });

  final String number;
  final int area;
  final String owner;

  /// The state's summary: P perfected, A approved (not yet proven),
  /// U unapproved, T terminated.
  final String summary;
  final String status;
  final String typeOfRight;

  /// Use codes, e.g. "IDS" (irrigation, domestic, stock).
  final String uses;

  /// Groundwater (wells). Cedar Valley-style groundwater management plans
  /// cut groundwater rights by priority, so this decides who it ranks against.
  final bool underground;
  final int podCount;

  /// Priority as YYYYMMDD; a year-only priority is YYYY0000.
  final int? priority;
  final double? acreFeet;
  final double? cfs;
  final String? source;
  final double? lat;
  final double? lng;
  final String? webLink;

  bool get proven => summary == 'P';
  bool get approvedOnly => summary == 'A';

  int? get priorityYear => priority == null ? null : priority! ~/ 10000;

  String get priorityLabel {
    final p = priority;
    if (p == null) return 'No date';
    final y = p ~/ 10000;
    final m = (p ~/ 100) % 100;
    final d = p % 100;
    if (m == 0) return '$y';
    return '${m.toString().padLeft(2, '0')}/${d.toString().padLeft(2, '0')}/$y';
  }

  /// Plain status: what the state calls it, or "Perfected" when it says
  /// nothing but the summary does.
  String get statusLabel =>
      status.isNotEmpty ? status : (proven ? 'Perfected' : summary);

  String get usesLabel {
    const map = {
      'I': 'Irrigation',
      'D': 'Domestic',
      'S': 'Stock',
      'M': 'Municipal',
      'P': 'Power',
      'O': 'Other',
      'X': 'Exchange',
      'F': 'Fish/Wildlife',
      'G': 'Geothermal',
      'R': 'Recreation',
      'C': 'Commercial',
      'N': 'Mining',
    };
    final names = <String>{for (final c in uses.split('')) map[c] ?? c}
      ..remove('');
    return names.isEmpty ? 'Not listed' : names.join(', ');
  }

  /// Held by a city, district, company, church or agency rather than a
  /// person or family. Those rarely sell; people and family farms do.
  bool get institutional {
    final o = ' ${owner.toUpperCase()} ';
    const words = [
      ' CITY ',
      ' TOWN ',
      ' COUNTY ',
      ' CORPORATION',
      ' CORP ',
      ' DISTRICT',
      ' IRRIGATION CO',
      ' WATER CO',
      ' WATER USERS',
      ' COMPANY',
      ' INC',
      ' ASSOCIATION',
      ' ASSN',
      ' STATE OF ',
      'UNITED STATES',
      ' USA ',
      ' BUREAU',
      ' DEPARTMENT',
      ' DIVISION',
      ' SCHOOL',
      ' TRUST LANDS',
      ' UNIVERSITY',
      ' CHURCH',
      ' LATTER-DAY',
      ' FOREST SERVICE',
      ' AUTHORITY',
      ' MUNICIPAL',
    ];
    return words.any(o.contains);
  }

  /// Distance in miles from a point, or null without coordinates.
  double? milesFrom(double lat2, double lng2) {
    final a = lat;
    final b = lng;
    if (a == null || b == null) return null;
    const r = 3958.8;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(lat2 - a);
    final dLng = rad(lng2 - b);
    final h =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(a)) *
            math.cos(rad(lat2)) *
            math.pow(math.sin(dLng / 2), 2);
    return 2 * r * math.asin(math.sqrt(h));
  }
}

/// Where a right stands in the line for water in its area.
class PriorityRank {
  const PriorityRank({
    required this.kindLabel,
    required this.total,
    required this.olderCount,
    required this.youngerCount,
    required this.acreFeetAhead,
    required this.acreFeetTotal,
  });

  /// "groundwater" or "surface water".
  final String kindLabel;

  /// Live rights of the same kind in the area that have a priority date.
  final int total;

  /// How many of those are senior to (older than) this right.
  final int olderCount;

  /// How many are junior to (newer than) this right.
  final int youngerCount;

  /// Acre-feet held by the senior rights (rough: some rights share a total).
  final double acreFeetAhead;
  final double acreFeetTotal;

  /// Share of the area's rights this one is senior to, 0 to 1.
  double get seniorTo => total == 0 ? 0 : youngerCount / total;
}

class WaterMarketClient {
  WaterMarketClient._();
  static final instance = WaterMarketClient._();

  final _areas = <int, Future<List<AreaRight>>>{};

  static int? areaOf(String rightNumber) {
    final m = RegExp(r'^(\d{1,3})-').firstMatch(rightNumber.trim());
    return m == null ? null : int.parse(m.group(1)!);
  }

  /// Every perfected or approved right in [area], one entry per right.
  /// Cached for the session; a failed load is retried next time.
  Future<List<AreaRight>> areaRights(int area) {
    final cached = _areas[area];
    if (cached != null) return cached;
    final future = _loadArea(area);
    _areas[area] = future;
    future.catchError((Object _) {
      _areas.remove(area);
      return <AreaRight>[];
    });
    return future;
  }

  Future<List<AreaRight>> _loadArea(int area) async {
    final where = "WRNUM LIKE '$area-%' AND SUMMARY_ST IN ('P','A')";
    final count = await _count(where);
    final pages = (count / _pageSize).ceil().clamp(0, 25);
    final results = await Future.wait([
      for (var i = 0; i < pages; i++) _page(where, i * _pageSize),
    ]);
    return _merge(results.expand((p) => p), area);
  }

  /// The water right area around a point: the one most rights near it
  /// belong to. Null outside Utah or where no rights are mapped.
  Future<int?> areaAt(double lat, double lng) async {
    for (final meters in [3000, 10000, 30000]) {
      final uri = Uri.parse('$_podUrl/query').replace(
        queryParameters: {
          'geometry': '$lng,$lat',
          'geometryType': 'esriGeometryPoint',
          'inSR': '4326',
          'spatialRel': 'esriSpatialRelIntersects',
          'distance': '$meters',
          'units': 'esriSRUnit_Meter',
          'outFields': 'WRNUM',
          'returnGeometry': 'false',
          'resultRecordCount': '500',
          'f': 'json',
        },
      );
      final json = await _get(uri);
      final counts = <int, int>{};
      for (final f in (json['features'] as List? ?? const [])) {
        final attrs = (f as Map<String, dynamic>)['attributes'] as Map?;
        final area = areaOf('${attrs?['WRNUM'] ?? ''}');
        if (area != null) counts[area] = (counts[area] ?? 0) + 1;
      }
      if (counts.isNotEmpty) {
        return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
      }
    }
    return null;
  }

  /// One right by number, in any status (so a lapsed right still shows up
  /// with the bad news).
  Future<AreaRight?> right(String number) async {
    final n = number.trim().replaceAll("'", "''");
    final area = areaOf(n);
    if (area == null) return null;
    final rows = await _page("WRNUM='$n'", 0);
    if (rows.isEmpty) return null;
    return _merge(rows, area).firstOrNull;
  }

  /// How [right] ranks by priority against the live rights of the same kind
  /// (groundwater or surface) in its area.
  Future<PriorityRank?> rank(AreaRight right) async {
    final p = right.priority;
    if (p == null) return null;
    final peers = (await areaRights(right.area))
        .where((r) => r.underground == right.underground && r.priority != null)
        .where((r) => r.number != right.number)
        .toList();
    var older = 0;
    var younger = 0;
    var afAhead = 0.0;
    var afTotal = 0.0;
    for (final r in peers) {
      final af = r.acreFeet ?? 0;
      afTotal += af;
      if (r.priority! < p) {
        older++;
        afAhead += af;
      } else if (r.priority! > p) {
        younger++;
      }
    }
    return PriorityRank(
      kindLabel: right.underground ? 'groundwater' : 'surface water',
      total: peers.length,
      olderCount: older,
      youngerCount: younger,
      acreFeetAhead: afAhead,
      acreFeetTotal: afTotal,
    );
  }

  // ── Fetching ──────────────────────────────────────────────────────────────

  Future<int> _count(String where) async {
    final uri = Uri.parse('$_podUrl/query').replace(
      queryParameters: {'where': where, 'returnCountOnly': 'true', 'f': 'json'},
    );
    final json = await _get(uri);
    return (json['count'] as num?)?.toInt() ?? 0;
  }

  Future<List<Map<String, dynamic>>> _page(String where, int offset) async {
    final uri = Uri.parse('$_podUrl/query').replace(
      queryParameters: {
        'where': where,
        'outFields': _outFields,
        'returnGeometry': 'true',
        'outSR': '4326',
        'geometryPrecision': '5',
        'orderByFields': 'OBJECTID',
        'resultOffset': '$offset',
        'resultRecordCount': '$_pageSize',
        'f': 'json',
      },
    );
    final json = await _get(uri);
    return [
      for (final f in (json['features'] as List? ?? const []))
        {
          ...((f as Map<String, dynamic>)['attributes']
                  as Map<String, dynamic>? ??
              const {}),
          if (f['geometry'] case {'x': final num x, 'y': final num y}) ...{
            'LNG': x.toDouble(),
            'LAT': y.toDouble(),
          },
        },
    ];
  }

  Future<Map<String, dynamic>> _get(Uri uri) async {
    final res = await http.get(uri).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw Exception('Water rights service returned ${res.statusCode}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['error'] != null) {
      debugPrint('Water rights service error: ${json['error']}');
      throw Exception('Water rights service error');
    }
    return json;
  }

  // ── Merging points of diversion into rights ───────────────────────────────

  static List<AreaRight> _merge(Iterable<Map<String, dynamic>> rows, int area) {
    final byNumber = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      final n = '${r['WRNUM'] ?? ''}'.trim();
      if (n.isEmpty) continue;
      (byNumber[n] ??= []).add(r);
    }
    return [
      for (final MapEntry(key: number, value: pods) in byNumber.entries)
        _fromPods(number, area, pods),
    ];
  }

  static AreaRight _fromPods(
    String number,
    int area,
    List<Map<String, dynamic>> pods,
  ) {
    String s(String k) {
      for (final p in pods) {
        final v = '${p[k] ?? ''}'.trim();
        if (v.isNotEmpty && v != 'null') return v;
      }
      return '';
    }

    double? maxOf(String k) {
      double? best;
      for (final p in pods) {
        final v = (p[k] as num?)?.toDouble();
        if (v != null && v > 0 && (best == null || v > best)) best = v;
      }
      return best;
    }

    final underground = pods.where((p) {
      final t = '${p['TYPE'] ?? ''}'.toLowerCase();
      return t.contains('underground') || t.contains('well');
    }).length;

    final first = pods.firstWhere(
      (p) => p['LAT'] != null,
      orElse: () => pods.first,
    );
    final web = s('WebLink');
    return AreaRight(
      number: number,
      area: area,
      owner: s('OWNER').isEmpty ? 'Owner not listed' : s('OWNER'),
      summary: s('SUMMARY_ST'),
      status: s('STATUS'),
      typeOfRight: s('TYPE_OF_RIGHT'),
      uses: s('USES'),
      underground: underground * 2 >= pods.length && underground > 0,
      podCount: pods.length,
      priority: _parsePriority(s('PRIORITY')),
      acreFeet: maxOf('ACFT'),
      cfs: maxOf('CFS'),
      source: s('SOURCE').isEmpty ? null : s('SOURCE'),
      lat: (first['LAT'] as num?)?.toDouble(),
      lng: (first['LNG'] as num?)?.toDouble(),
      webLink: web.isNotEmpty
          ? web
          : 'https://www.waterrights.utah.gov/search/?q=${Uri.encodeComponent(number)}',
    );
  }

  /// "19350615" or "1856" to a sortable YYYYMMDD int.
  static int? _parsePriority(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 8) return int.tryParse(digits.substring(0, 8));
    if (digits.length == 4) {
      final y = int.tryParse(digits);
      return y == null ? null : y * 10000;
    }
    return null;
  }
}
