import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:prior/core/lookup_counter.dart';
import 'package:prior/core/lookup_gate.dart';
import 'package:prior/core/purchases_service.dart';
import 'package:prior/core/water_market_client.dart';
import 'package:prior/core/water_rights_client.dart';
import 'package:prior/features/paywall/paywall_sheet.dart';
import 'package:prior/features/saved/save_right_button.dart';
import 'package:url_launcher/url_launcher.dart';

/// "Is this right worth buying?": one Utah right with what a buyer, an
/// agent or a city would ask about it, in plain English.
class RightCheckScreen extends ConsumerStatefulWidget {
  const RightCheckScreen({required this.number, this.free = false, super.key});

  final String number;

  /// Opened from a lookup the user already spent: doesn't count again.
  final bool free;

  @override
  ConsumerState<RightCheckScreen> createState() => _RightCheckScreenState();
}

class _RightCheckScreenState extends ConsumerState<RightCheckScreen> {
  /// Null while checking the free lookup count.
  bool? _allowed;
  Future<AreaRight?>? _right;
  Future<PriorityRank?>? _rank;
  Future<List<ChangeApplication>>? _changes;

  Future<List<ChangeApplication>> _fetchChanges() => WaterRightsClient.instance
      .fetchChangeApps(widget.number, throwOnError: true);

  @override
  void initState() {
    super.initState();
    _gate();
  }

  Future<void> _gate() async {
    final ok = widget.free || await spendLookup(ref);
    if (!mounted) return;
    setState(() {
      _allowed = ok;
      if (ok) _load();
    });
  }

  Future<void> _upgrade() async {
    await showPaywallSheet(
      context,
      reason:
          "You've used your ${LookupCounter.freeLimit} free lookups this "
          'month. Each right check counts as one.',
    );
    if (!mounted) return;
    final pro = await ref.read(isSubscribedProvider.future);
    if (pro && mounted) {
      setState(() {
        _allowed = true;
        _load();
      });
    }
  }

  void _load() {
    // The rank is chained rather than set in a then() with setState: a
    // setState callback that returns a Future throws in debug builds, which
    // failed the whole page.
    final right = WaterMarketClient.instance.right(widget.number);
    _right = right;
    _rank = right.then(
      (r) => r == null ? null : WaterMarketClient.instance.rank(r),
    );
    _changes ??= _fetchChanges();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Right ${widget.number}'),
        actions: [
          // Save it once it's loaded (Saved keeps a snapshot of the right).
          if (_allowed ?? false)
            FutureBuilder<AreaRight?>(
              future: _right,
              builder: (context, snap) {
                final r = snap.data;
                return r == null
                    ? const SizedBox.shrink()
                    : SaveRightButton(right: r);
              },
            ),
        ],
      ),
      body: _allowed == null
          ? const Center(child: CircularProgressIndicator())
          : _allowed == false
          ? _Locked(onUpgrade: _upgrade)
          : FutureBuilder<AreaRight?>(
              future: _right,
              builder: (context, snap) {
                if (snap.hasError) {
                  return _Retry(
                    text: "Couldn't reach the state water rights data.",
                    onRetry: () => setState(_load),
                  );
                }
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final r = snap.data;
                if (r == null) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'No Utah water right ${widget.number} was found.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return _Body(
                  right: r,
                  rank: _rank,
                  changes: _changes!,
                  onRetryChanges: () => setState(() {
                    _changes = _fetchChanges();
                  }),
                );
              },
            ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.right,
    required this.changes,
    required this.onRetryChanges,
    this.rank,
  });

  final AreaRight right;
  final VoidCallback onRetryChanges;
  final Future<PriorityRank?>? rank;
  final Future<List<ChangeApplication>> changes;

  @override
  Widget build(BuildContext context) {
    final r = right;
    final text = Theme.of(context).textTheme;
    final af = r.acreFeet;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          r.owner,
          style: text.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          [
            'Priority ${r.priorityLabel}',
            if (af != null) '${_num(af)} acre-ft/yr',
            if (r.cfs != null) '${r.cfs!.toStringAsFixed(3)} cfs',
          ].join(' · '),
          style: text.bodyMedium,
        ),
        Text(
          [
            r.usesLabel,
            if (r.underground) 'Groundwater' else 'Surface water',
            if (r.source != null) r.source!,
          ].join(' · '),
          style: text.bodySmall,
        ),
        const SizedBox(height: 16),
        _status(r),
        ?_typeNote(r),
        _quantity(r),
        _RankCheck(right: r, rank: rank),
        _ChangesCheck(changes: changes, onRetry: onRetryChanges),
        _Check(
          level: _Level.info,
          title: 'Stays in area ${r.area}',
          body:
              'A Utah right can generally only be moved within its own area. '
              'Moving it to a new place or use takes a change application to '
              'the State Engineer, and others can protest it. Ask the city '
              'whether it accepts water from this right before you buy.',
        ),
        if (r.podCount > 1)
          _Check(
            level: _Level.info,
            title: '${r.podCount} points of diversion',
            body:
                'This right can be taken from ${r.podCount} wells or '
                "diversions. The amount above is the right's total, not per "
                'point.',
          ),
        const SizedBox(height: 16),
        FilledButton.icon(
          icon: const Icon(Icons.open_in_new),
          label: const Text('Open the state record'),
          onPressed: r.webLink == null
              ? null
              : () => launchUrl(
                  Uri.parse(r.webLink!),
                  mode: LaunchMode.externalApplication,
                ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.travel_explore),
          label: Text('Other rights in area ${r.area}'),
          onPressed: () => context.push('/find-water?area=${r.area}'),
        ),
        const SizedBox(height: 16),
        Text(
          "From the Utah Division of Water Rights' public data. This isn't a "
          'title search: confirm ownership, quantity and transferability with '
          'the Division, the city and a water rights attorney before buying.',
          style: text.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      ],
    );
  }

  Widget _status(AreaRight r) {
    final s = r.statusLabel;
    final lower = s.toLowerCase();
    if (r.summary == 'T') {
      return _Check(
        level: _Level.bad,
        title: s,
        body:
            'This right is no longer in good standing (lapsed, withdrawn, '
            'expired or similar). There may be no water left to buy.',
      );
    }
    if (r.summary == 'U') {
      return const _Check(
        level: _Level.warn,
        title: 'Unapproved application',
        body: 'Only an application so far. Nothing has been granted yet.',
      );
    }
    if (r.approvedOnly) {
      return const _Check(
        level: _Level.warn,
        title: 'Approved, not yet proven',
        body:
            "The State Engineer approved it, but the owner hasn't yet proven "
            "the water was put to use. If proof isn't filed in time it can "
            'lapse. Many cities want proven water, so ask first.',
      );
    }
    if (lower.contains('certificated')) {
      return const _Check(
        level: _Level.good,
        title: 'Certificated',
        body:
            'Proven: the State Engineer certified the water was put to use. '
            'The strongest kind of Utah right.',
      );
    }
    if (lower.contains('claim')) {
      return _Check(
        level: _Level.good,
        title: s,
        body:
            'Recognized through a claim in a court adjudication. The final '
            'decree for the area can still adjust it.',
      );
    }
    return _Check(
      level: _Level.good,
      title: s,
      body: 'Perfected: an established right, by decree or proven use.',
    );
  }

  Widget? _typeNote(AreaRight r) {
    final t = r.typeOfRight.toLowerCase();
    if (t.contains('diligence')) {
      return const _Check(
        level: _Level.info,
        title: 'Diligence claim',
        body:
            'A claim to surface water used before 1903, when permits began. '
            "It isn't verified until the area is adjudicated.",
      );
    }
    if (t.contains('underground water claim')) {
      return const _Check(
        level: _Level.info,
        title: 'Underground water claim',
        body:
            'A claim to well water used before 1935, when groundwater permits '
            'began.',
      );
    }
    if (t.contains('shares')) {
      return const _Check(
        level: _Level.info,
        title: 'Water company shares',
        body:
            'Held as shares in a water company. Shares are bought through the '
            'company, and its rules decide whether they can move.',
      );
    }
    return null;
  }

  Widget _quantity(AreaRight r) {
    final af = r.acreFeet;
    if (af == null) {
      return const _Check(
        level: _Level.warn,
        title: 'No acre-feet listed',
        body:
            'The state data shows no yearly volume. It may be flow-only, '
            'share a total with other rights, or be stock watering. Check the '
            'state record before counting on any amount.',
      );
    }
    if (r.uses == 'S') {
      return _Check(
        level: _Level.warn,
        title: '${_num(af)} acre-ft, stock watering only',
        body:
            'Rights only for stock watering are small and seldom accepted for '
            'development.',
      );
    }
    return _Check(
      level: _Level.info,
      title: '${_num(af)} acre-ft per year',
      body:
          'The yearly volume on record. Where it shares a total with other '
          'rights (a supplemental group), the usable amount can be less. The '
          'state record shows any group.',
    );
  }
}

class _RankCheck extends StatelessWidget {
  const _RankCheck({required this.right, this.rank});

  final AreaRight right;
  final Future<PriorityRank?>? rank;

  @override
  Widget build(BuildContext context) {
    if (right.priority == null) {
      return const _Check(
        level: _Level.warn,
        title: 'No priority date',
        body: "Without a priority date, it can't be ranked against others.",
      );
    }
    final f = rank;
    if (f == null) return const _Loading('Ranking against the area…');
    return FutureBuilder<PriorityRank?>(
      future: f,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _Loading('Ranking against the area…');
        }
        final k = snap.data;
        if (k == null || k.total == 0) return const SizedBox.shrink();
        final pct = (k.seniorTo * 100).round();
        final fmt = NumberFormat.decimalPattern();
        final level = pct >= 70
            ? _Level.good
            : pct >= 35
            ? _Level.info
            : _Level.warn;
        return _Check(
          level: level,
          title: "Older than $pct% of the area's ${k.kindLabel} rights",
          body:
              '${fmt.format(k.olderCount)} of ${fmt.format(k.total)} live '
              '${k.kindLabel} rights in area ${right.area} are older, holding '
              'about ${fmt.format(k.acreFeetAhead.round())} acre-ft. '
              '${right.underground ? 'Where a groundwater management plan applies, as in Cedar Valley, cutbacks go by priority date and the newest rights are cut first, so older is safer.' : 'In a short year, older rights on a source are filled first.'}',
        );
      },
    );
  }
}

class _ChangesCheck extends StatelessWidget {
  const _ChangesCheck({required this.changes, required this.onRetry});

  final Future<List<ChangeApplication>> changes;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ChangeApplication>>(
      future: changes,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _Loading('Checking change applications…');
        }
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(
                  child: _Check(
                    level: _Level.warn,
                    title: "Couldn't check change applications",
                    body:
                        "The state's records site didn't answer. Try again, "
                        'or look under Changes in the state record.',
                  ),
                ),
                TextButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            ),
          );
        }
        final all = snap.data ?? const <ChangeApplication>[];
        final pending = all.where((a) => a.isPending).toList();
        if (pending.isNotEmpty) {
          return _Check(
            level: _Level.warn,
            title:
                '${pending.length} pending change application'
                '${pending.length == 1 ? '' : 's'}',
            body:
                'Someone has asked to move or change this water: '
                '${pending.map((a) => '${a.appNumber} (filed ${a.filedDate})').join(', ')}. '
                'Find out what it does before buying.',
          );
        }
        if (all.isNotEmpty) {
          return _Check(
            level: _Level.info,
            title: 'Changed before',
            body:
                '${all.length} past change application'
                '${all.length == 1 ? '' : 's'}, none pending. The state record '
                'shows where and how the water is used now.',
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

enum _Level { good, info, warn, bad }

class _Check extends StatelessWidget {
  const _Check({required this.level, required this.title, required this.body});

  final _Level level;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (icon, color) = switch (level) {
      _Level.good => (Icons.check_circle, Colors.green[600]!),
      _Level.info => (Icons.info_outline, cs.primary),
      _Level.warn => (Icons.warning_amber_rounded, Colors.orange[700]!),
      _Level.bad => (Icons.cancel, cs.error),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(body, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: Padding(
              padding: EdgeInsets.all(3),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          const SizedBox(width: 12),
          Text(text, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _Retry extends StatelessWidget {
  const _Retry({required this.text, required this.onRetry});

  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}

String _num(double v) =>
    v >= 100 ? v.round().toString() : v.toStringAsFixed(v < 10 ? 2 : 1);

class _Locked extends StatelessWidget {
  const _Locked({required this.onUpgrade});

  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 48, color: cs.primary),
            const SizedBox(height: 12),
            const Text(
              "You've used this month's free lookups",
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            const Text(
              'Prior Pro checks any right: its standing, how it ranks for '
              'water in its area, and any pending changes.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onUpgrade,
              child: const Text('Unlock Prior Pro'),
            ),
          ],
        ),
      ),
    );
  }
}
