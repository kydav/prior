import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:prior/core/saved_lookups.dart';

/// Saved: the user's working list, in two tabs.
/// - **Places**: parcels and points from the map. Tapping one returns it to
///   the map, which looks it up again.
/// - **Water rights**: rights saved from Find water or a right check.
///   Tapping one opens its right check, fresh.
class SavedScreen extends StatelessWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Saved'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Places'),
              Tab(text: 'Water rights'),
            ],
          ),
        ),
        body: StreamBuilder<List<SavedLookup>>(
          stream: SavedLookups.instance.watch(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final all = snap.data!;
            return TabBarView(
              children: [
                _SavedList(
                  items: [
                    for (final s in all)
                      if (!s.isRight) s,
                  ],
                  empty:
                      'No places saved yet.\nLook up a property, then tap '
                      'Save to keep it here with your own notes.',
                ),
                _SavedList(
                  items: [
                    for (final s in all)
                      if (s.isRight) s,
                  ],
                  empty:
                      'No water rights saved yet.\nIn Find water or a right '
                      'check, tap the bookmark to keep a right here.',
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SavedList extends StatelessWidget {
  const _SavedList({required this.items, required this.empty});

  final List<SavedLookup> items;
  final String empty;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            empty,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) => _SavedTile(saved: items[i]),
    );
  }
}

class _SavedTile extends StatelessWidget {
  const _SavedTile({required this.saved});

  final SavedLookup saved;

  static final _date = DateFormat.yMMMd();

  /// The line under the name: how it stood when saved.
  String get _facts {
    final s = saved;
    if (s.isRight) {
      final af = s.acreFeet;
      return [
        if (s.title != s.rightNumber && !s.title.contains(s.rightNumber))
          s.rightNumber,
        if (s.status.isNotEmpty) s.status,
        if (af != null) '${af >= 100 ? af.round() : af.toStringAsFixed(1)} af',
        if (s.uses.isNotEmpty) s.uses,
        _date.format(s.savedAt),
      ].join(' · ');
    }
    final rights = s.rightNumbers.length;
    return [
      if (s.state.isNotEmpty) s.state,
      '$rights right${rights == 1 ? '' : 's'} when saved',
      _date.format(s.savedAt),
    ].join(' · ');
  }

  Future<void> _edit(BuildContext context) async {
    final s = saved;
    final title = TextEditingController(text: s.title);
    final note = TextEditingController(text: s.note);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.isRight ? 'Edit saved right' : 'Edit saved place'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: note,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Note'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      await SavedLookups.instance.update(
        s.id,
        title: title.text,
        note: note.text,
      );
    }
    title.dispose();
    note.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = saved;
    return Dismissible(
      key: ValueKey(s.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red.shade700,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => SavedLookups.instance.delete(s.id),
      child: ListTile(
        leading: Icon(
          s.isRight ? Icons.water_drop : Icons.bookmark,
          color: Colors.lightBlue,
        ),
        title: Text(s.title),
        subtitle: Text(
          [if (s.note.isNotEmpty) s.note, _facts].join('\n'),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: s.note.isNotEmpty,
        // A place goes back to the map; a right opens its check (which
        // counts as a lookup for free users, like any right check).
        onTap: () => s.isRight
            ? context.push('/right/${Uri.encodeComponent(s.rightNumber)}')
            : context.pop(s),
        trailing: IconButton(
          tooltip: 'Edit',
          icon: const Icon(Icons.edit_outlined),
          onPressed: () => _edit(context),
        ),
      ),
    );
  }
}
