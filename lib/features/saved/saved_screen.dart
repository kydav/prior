import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:prior/core/saved_lookups.dart';

/// Saved lookups: a working list of the listings and parcels the user is
/// tracking. Tapping one returns it to the map, which looks it up again.
class SavedScreen extends StatelessWidget {
  const SavedScreen({super.key});

  Future<void> _edit(BuildContext context, SavedLookup s) async {
    final title = TextEditingController(text: s.title);
    final note = TextEditingController(text: s.note);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit saved lookup'),
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
    final date = DateFormat.yMMMd();
    return Scaffold(
      appBar: AppBar(title: const Text('Saved Lookups')),
      body: StreamBuilder<List<SavedLookup>>(
        stream: SavedLookups.instance.watch(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final saved = snap.data!;
          if (saved.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Nothing saved yet.\nLook up a property, then tap the '
                  'bookmark to keep it here with your own notes.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: saved.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final s = saved[i];
              final rights = s.rightNumbers.length;
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
                  leading: const Icon(Icons.bookmark, color: Colors.lightBlue),
                  title: Text(s.title),
                  subtitle: Text(
                    [
                      if (s.note.isNotEmpty) s.note,
                      [
                        if (s.state.isNotEmpty) s.state,
                        '$rights right${rights == 1 ? '' : 's'} when saved',
                        date.format(s.savedAt),
                      ].join(' · '),
                    ].join('\n'),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  isThreeLine: s.note.isNotEmpty,
                  onTap: () => context.pop(s),
                  trailing: IconButton(
                    tooltip: 'Edit',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _edit(context, s),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
