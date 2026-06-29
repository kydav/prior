import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:prior/data/water_right.dart';

class WaterHubClient {
  WaterHubClient._();
  static final instance = WaterHubClient._();

  static const _listingsUrl = 'https://utahwaterhub.com/listings';
  static const _cacheKey = 'whub_listings';
  static const _tsKey = 'whub_ts';
  static const _ttlSeconds = 6 * 3600;

  List<WaterHubListing>? _memCache;
  int? _memCacheTs; // epoch seconds

  Future<List<WaterHubListing>> listingsForArea(int area) async {
    try {
      final all = await _allListings();
      return all.where((l) => l.isWaterRight && l.policyArea == area).toList();
    } catch (e) {
      debugPrint('WaterHub area lookup error: $e');
      return [];
    }
  }

  Future<List<WaterHubListing>> _allListings() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // Memory cache
    if (_memCache != null &&
        _memCacheTs != null &&
        now - _memCacheTs! < _ttlSeconds) {
      return _memCache!;
    }

    // SharedPreferences cache
    try {
      final prefs = await SharedPreferences.getInstance();
      final ts = prefs.getInt(_tsKey) ?? 0;
      if (now - ts < _ttlSeconds) {
        final raw = prefs.getString(_cacheKey);
        if (raw != null) {
          final listings = (jsonDecode(raw) as List)
              .map((e) => WaterHubListing.fromJson(e as Map<String, dynamic>))
              .toList();
          _memCache = listings;
          _memCacheTs = ts;
          return listings;
        }
      }
    } catch (e) {
      debugPrint('WaterHub prefs read error: $e');
    }

    return _fetchAndCache();
  }

  Future<List<WaterHubListing>> _fetchAndCache() async {
    try {
      final res = await http
          .get(
            Uri.parse(_listingsUrl),
            headers: {'User-Agent': 'Mozilla/5.0'},
          )
          .timeout(const Duration(seconds: 12));

      if (res.statusCode != 200) return _memCache ?? [];

      final listings = _parseListings(res.body);
      if (listings.isEmpty) return _memCache ?? [];

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      _memCache = listings;
      _memCacheTs = now;

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          _cacheKey,
          jsonEncode(listings.map((l) => l.toJson()).toList()),
        );
        await prefs.setInt(_tsKey, now);
      } catch (e) {
        debugPrint('WaterHub prefs write error: $e');
      }

      return listings;
    } catch (e) {
      debugPrint('WaterHub fetch error: $e');
      return _memCache ?? [];
    }
  }

  List<WaterHubListing> _parseListings(String html) {
    // Strip React rendering comments before matching
    final cleaned = html.replaceAll(RegExp(r'<!--.*?-->'), '');
    final results = <WaterHubListing>[];

    final cardPattern = RegExp(
      r'<a\s+id="listing-row-[^"]*"\s[^>]*href="(/listings/[^"]+)"[^>]*>(.*?)</a>',
      dotAll: true,
    );

    for (final m in cardPattern.allMatches(cleaned)) {
      try {
        final url = m.group(1)!;
        final inner = m.group(2)!;

        final titleMatch =
            RegExp(r'<h2[^>]*>([^<]+)</h2>').firstMatch(inner);
        if (titleMatch == null) continue;
        final title = titleMatch.group(1)!.trim();

        // "Beaver, Millard · Policy area 71"
        final metaMatch = RegExp(
          r'text-ink-mute\s+mt-1[^>]*>([^<]+)</p>',
        ).firstMatch(inner);
        final meta = metaMatch?.group(1)?.trim() ?? '';

        final areaMatch = RegExp(r'Policy area (\d+)').firstMatch(meta);
        final area = areaMatch != null ? int.tryParse(areaMatch.group(1)!) : null;

        String? county;
        if (meta.contains('·')) {
          final c = meta.split('·').first.trim();
          county = c.isEmpty ? null : c;
        } else if (area == null) {
          county = meta.isEmpty ? null : meta;
        }

        final isWaterRight = inner.contains('chip-sage');

        // Quantity: font-mono text-sm text-ink (not text-ink-mute)
        final qtyMatch = RegExp(
          r'font-mono text-sm text-ink[^-][^>]*>([^<]+)<',
        ).firstMatch(inner);
        final qtyRaw = qtyMatch?.group(1)?.trim() ?? '';
        final quantity = qtyRaw.isEmpty ? null : qtyRaw;

        // Price: md:text-right div
        final priceMatch = RegExp(
          r'md:text-right[^>]*>([^<]+)<',
        ).firstMatch(inner);
        final priceRaw = priceMatch?.group(1)?.trim() ?? '';
        final price = priceRaw.isEmpty ? null : priceRaw;

        // ID: last hyphen-segment of slug (8-char UUID prefix)
        final slugParts = url.split('/').last.split('-');
        final id = slugParts.last;

        results.add(WaterHubListing(
          id: id,
          title: title,
          url: url,
          policyArea: area,
          county: county,
          quantity: quantity,
          price: price,
          isWaterRight: isWaterRight,
        ));
      } catch (e) {
        debugPrint('WaterHub card parse error: $e');
      }
    }

    return results;
  }
}
