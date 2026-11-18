import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:prior/core/purchases_service.dart';
import 'package:prior/core/water_hub_client.dart';
import 'package:prior/core/water_market_client.dart';
import 'package:prior/core/water_rights_client.dart';
import 'package:prior/data/water_right.dart';
import 'package:prior/features/paywall/paywall_sheet.dart';
import 'package:url_launcher/url_launcher.dart';

/// "Who holds water around here?": every live right in a Utah water right
/// area, filtered the way a buyer shops (use, source, seniority, size) and
/// with what's listed for sale in the same area on top.
class AreaSearchScreen extends ConsumerStatefulWidget {
  const AreaSearchScreen({this.initialArea, super.key});

  /// Opens straight to an area (from a right's "Other rights in area").
  final int? initialArea;

  @override
  ConsumerState<AreaSearchScreen> createState() => _AreaSearchScreenState();
}

/// Rights a free user sees per search before the Pro teaser.
const _freePreview = 3;

enum _Use { any, irrigation, municipal, domestic, stock }

enum _Source { any, ground, surface }

enum _Sort { oldest, largest }

class _AreaSearchScreenState extends ConsumerState<AreaSearchScreen> {
  final _query = TextEditingController();

  int? _area;
  String? _placeName;
  (double, double)? _center;
  Future<List<AreaRight>>? _rights;
  Future<List<WaterHubListing>>? _listings;
  String? _error;
  bool _finding = false;

  // Filters
  _Use _use = _Use.any;
  _Source _source = _Source.any;
  _Sort _sort = _Sort.oldest;
  bool _provenOnly = true;
  bool _peopleOnly = false;
  double _minAcreFeet = 0;
  double? _withinMiles;

  @override
  void initState() {
    super.initState();
    final a = widget.initialArea;
    if (a != null) {
      _query.text = '$a';
      _open(a);
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _open(int area, {String? place, (double, double)? center}) {
    setState(() {
      _area = area;
      _placeName = place;
      _center = center;
      _withinMiles = center == null ? null : _withinMiles;
      _error = null;
      _rights = WaterMarketClient.instance.areaRights(area);
      _listings = WaterHubClient.instance.listingsForArea(area);
    });
  }

  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();

    final asArea = int.tryParse(q);
    if (asArea != null && asArea > 0 && asArea < 1000 && q.length <= 3) {
      _open(asArea);
      return;
    }
    // A right number opens the right check instead.
    if (RegExp(r'^\d{1,3}-\d{1,7}$').hasMatch(q)) {
      await context.push('/right/$q');
      return;
    }

    setState(() {
      _finding = true;
      _error = null;
    });
    try {
      final hasState = RegExp(r'\b(UT|Utah)\b', caseSensitive: false);
      final at = await WaterRightsClient.instance.geocodePlace(
        hasState.hasMatch(q) ? q : '$q, Utah',
      );
      if (at == null) {
        setState(() => _error = 'Couldn\'t find "$q" in Utah.');
        return;
      }
      final area = await WaterMarketClient.instance.areaAt(at.$1, at.$2);
      if (area == null) {
        setState(() => _error = 'No Utah water rights are mapped near "$q".');
        return;
      }
      _open(area, place: q, center: at);
    } catch (_) {
      setState(() => _error = "Couldn't reach the state water rights data.");
    } finally {
      if (mounted) setState(() => _finding = false);
    }
  }

  List<AreaRight> _filter(List<AreaRight> all) {
    final c = _center;
    final within = _withinMiles;
    final out = all.where((r) {
      if (_provenOnly && !r.proven) return false;
      if (_peopleOnly && r.institutional) return false;
      if ((r.acreFeet ?? 0) < _minAcreFeet) return false;
      switch (_source) {
        case _Source.ground:
          if (!r.underground) return false;
        case _Source.surface:
          if (r.underground) return false;
        case _Source.any:
      }
      final code = switch (_use) {
        _Use.any => null,
        _Use.irrigation => 'I',
        _Use.municipal => 'M',
        _Use.domestic => 'D',
        _Use.stock => 'S',
      };
      if (code != null && !r.uses.contains(code)) return false;
      if (c != null && within != null) {
        final d = r.milesFrom(c.$1, c.$2);
        if (d == null || d > within) return false;
      }
      return true;
    }).toList();
    switch (_sort) {
      case _Sort.oldest:
        out.sort(
          (a, b) => (a.priority ?? 99999999).compareTo(b.priority ?? 99999999),
        );
      case _Sort.largest:
        out.sort((a, b) => (b.acreFeet ?? 0).compareTo(a.acreFeet ?? 0));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Find water')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _query,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: 'Town, area # (73) or right # (73-1234)',
                prefixIcon: const Icon(Icons.travel_explore),
                suffixIcon: _finding
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.arrow_forward),
                        onPressed: _search,
                      ),
              ),
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_error != null) {
      return _Message(icon: Icons.search_off, text: _error!);
    }
    final rights = _rights;
    if (rights == null) {
      return const _Message(
        icon: Icons.water_drop_outlined,
        text:
            'Search a town like "Enoch" to see every water right in its '
            'area: who owns it, how old it is and how much water it carries.\n\n'
            'Utah rights can usually only be moved within their own area, '
            'so the area is the market.',
      );
    }
    return FutureBuilder<List<AreaRight>>(
      future: rights,
      builder: (context, snap) {
        if (snap.hasError) {
          return const _Message(
            icon: Icons.cloud_off,
            text:
                "Couldn't load this area. Check your connection and try again.",
          );
        }
        if (!snap.hasData) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Loading every right in the area…'),
              ],
            ),
          );
        }
        final shown = _filter(snap.data!);
        final pro = ref.watch(isSubscribedProvider).valueOrNull ?? false;
        final visible = pro
            ? shown.length.clamp(0, 300)
            : shown.length.clamp(0, _freePreview);
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _filters()),
            SliverToBoxAdapter(child: _summary(shown, snap.data!.length)),
            SliverToBoxAdapter(child: _forSale()),
            SliverList.separated(
              itemCount: visible,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) => _RightTile(
                right: shown[i],
                center: _center,
                onTap: () => context.push('/right/${shown[i].number}'),
              ),
            ),
            if (!pro && shown.length > _freePreview)
              SliverToBoxAdapter(
                child: _ProTeaser(hidden: shown.length - _freePreview),
              ),
            if (pro && shown.length > 300)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Showing the first 300. Narrow the filters to see the rest.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        );
      },
    );
  }

  Widget _filters() {
    Widget chip<T>(String label, T value, T current, ValueChanged<T> set) =>
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(
            label: Text(label),
            selected: value == current,
            onSelected: (_) => setState(() => set(value)),
          ),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (label, v) in [
                  ('Any use', _Use.any),
                  ('Irrigation', _Use.irrigation),
                  ('Municipal', _Use.municipal),
                  ('Domestic', _Use.domestic),
                  ('Stock', _Use.stock),
                ])
                  chip(label, v, _use, (x) => _use = x),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (label, v) in [
                  ('Wells & surface', _Source.any),
                  ('Groundwater', _Source.ground),
                  ('Surface', _Source.surface),
                ])
                  chip(label, v, _source, (x) => _source = x),
                const SizedBox(width: 8),
                chip('Oldest first', _Sort.oldest, _sort, (x) => _sort = x),
                chip('Most water', _Sort.largest, _sort, (x) => _sort = x),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: const Text('Proven only'),
                    selected: _provenOnly,
                    onSelected: (v) => setState(() => _provenOnly = v),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: const Text('People & farms only'),
                    selected: _peopleOnly,
                    onSelected: (v) => setState(() => _peopleOnly = v),
                  ),
                ),
                if (_center != null)
                  for (final miles in [null, 5.0, 10.0])
                    chip(
                      miles == null
                          ? 'Whole area'
                          : 'Within ${miles.toInt()} mi',
                      miles,
                      _withinMiles,
                      (x) => _withinMiles = x,
                    ),
              ],
            ),
          ),
          Row(
            children: [
              Text(
                _minAcreFeet == 0
                    ? 'Any size'
                    : 'At least ${_minAcreFeet.toInt()} acre-ft',
              ),
              Expanded(
                child: Slider(
                  value: _minAcreFeet,
                  max: 100,
                  divisions: 20,
                  label: '${_minAcreFeet.toInt()} acre-ft',
                  onChanged: (v) => setState(() => _minAcreFeet = v),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summary(List<AreaRight> shown, int total) {
    final af = shown.fold<double>(0, (s, r) => s + (r.acreFeet ?? 0));
    final fmt = NumberFormat.decimalPattern();
    final where = _placeName == null ? '' : ' · around $_placeName';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Area $_area$where',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          Text(
            '${fmt.format(shown.length)} of ${fmt.format(total)} rights · '
            'about ${fmt.format(af.round())} acre-ft listed',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _forSale() {
    final listings = _listings;
    if (listings == null) return const SizedBox.shrink();
    return FutureBuilder<List<WaterHubListing>>(
      future: listings,
      builder: (context, snap) {
        final list = snap.data;
        if (list == null || list.isEmpty) return const SizedBox.shrink();
        return Card(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: ExpansionTile(
            leading: Icon(Icons.sell_outlined, color: Colors.green[600]),
            title: Text(
              '${list.length} listed for sale in area $_area',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: const Text('via Utah Water Hub'),
            children: [
              for (final l in list)
                ListTile(
                  dense: true,
                  title: Text(l.title),
                  subtitle: Text(
                    [
                      l.quantity,
                      l.price,
                      l.county,
                    ].whereType<String>().join(' · '),
                  ),
                  trailing: const Icon(Icons.open_in_new, size: 16),
                  onTap: () => launchUrl(
                    Uri.parse(l.hubUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _RightTile extends StatelessWidget {
  const _RightTile({required this.right, required this.onTap, this.center});

  final AreaRight right;
  final (double, double)? center;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = center;
    final miles = c == null ? null : right.milesFrom(c.$1, c.$2);
    final af = right.acreFeet;
    final bits = [
      right.priorityLabel,
      right.usesLabel,
      if (right.underground) 'Well' else 'Surface',
      if (miles != null) '${miles.toStringAsFixed(1)} mi',
    ];
    return ListTile(
      onTap: onTap,
      title: Text(right.owner, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${right.number} · ${bits.join(' · ')}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            af == null ? '—' : '${_af(af)} af',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          if (right.approvedOnly)
            Text(
              'Not proven',
              style: TextStyle(fontSize: 11, color: Colors.orange[700]),
            ),
        ],
      ),
    );
  }

  static String _af(double v) =>
      v >= 100 ? v.round().toString() : v.toStringAsFixed(v < 10 ? 2 : 1);
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _ProTeaser extends StatelessWidget {
  const _ProTeaser({required this.hidden});

  final int hidden;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fmt = NumberFormat.decimalPattern();
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(Icons.lock_outline, color: cs.primary),
            const SizedBox(height: 8),
            Text(
              '${fmt.format(hidden)} more rights match',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            const SizedBox(height: 4),
            const Text(
              'See every owner, priority date and amount in the area, and '
              'check any right, with Prior Pro.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => showPaywallSheet(
                context,
                reason:
                    'See every water right in the area and check any of them.',
              ),
              child: const Text('Unlock Prior Pro'),
            ),
          ],
        ),
      ),
    );
  }
}
