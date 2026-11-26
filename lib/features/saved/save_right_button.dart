import 'package:flutter/material.dart';
import 'package:prior/core/saved_lookups.dart';
import 'package:prior/core/water_market_client.dart';

/// Asks for a name and note before saving. Null if cancelled.
Future<({String title, String note})?> askSaveDetails(
  BuildContext context, {
  required String heading,
  required String suggestedTitle,
  String hint = 'e.g. Smith listing, ask about well share',
}) async {
  final title = TextEditingController(text: suggestedTitle);
  final note = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(heading),
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
            decoration: InputDecoration(
              labelText: 'Note (optional)',
              hintText: hint,
            ),
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
  final result = (ok ?? false) ? (title: title.text, note: note.text) : null;
  title.dispose();
  note.dispose();
  return result;
}

/// A bookmark for one water right: tap to save it (with a name and note),
/// tap again to take it out of Saved. Shows filled when it's saved.
///
/// A list of many rights passes [saved] from one shared watch of Saved;
/// otherwise the button watches Saved itself.
class SaveRightButton extends StatelessWidget {
  const SaveRightButton({required this.right, this.saved, super.key});

  final AreaRight right;
  final bool? saved;

  Future<void> _toggle(BuildContext context, bool saved) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (saved) {
        await SavedLookups.instance.deleteRight(right.number);
        messenger.showSnackBar(
          SnackBar(content: Text('Removed ${right.number} from Saved')),
        );
        return;
      }
      final details = await askSaveDetails(
        context,
        heading: 'Save water right',
        suggestedTitle: SavedLookups.suggestedRightTitle(right),
        hint: 'e.g. Asking \$12k/af, call owner',
      );
      if (details == null) return;
      await SavedLookups.instance.saveRight(
        right,
        title: details.title,
        note: details.note,
      );
      messenger.showSnackBar(SnackBar(content: Text('Saved ${right.number}')));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't save. Try again.")),
      );
    }
  }

  Widget _button(BuildContext context, bool? isSaved) {
    final on = isSaved ?? false;
    return IconButton(
      tooltip: on ? 'Remove from Saved' : 'Save this right',
      icon: Icon(
        on ? Icons.bookmark : Icons.bookmark_add_outlined,
        color: on ? Colors.lightBlue : null,
      ),
      onPressed: isSaved == null ? null : () => _toggle(context, on),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (saved != null) return _button(context, saved);
    return StreamBuilder<Set<String>>(
      stream: SavedLookups.instance.watchSavedRights(),
      builder: (context, snap) =>
          _button(context, snap.data?.contains(right.number)),
    );
  }
}
