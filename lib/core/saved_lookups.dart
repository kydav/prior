import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:prior/core/water_rights_client.dart';

/// A lookup the user kept: where it was, a name and note of their own, and a
/// snapshot of what was found then (`users/{uid}/saved/{id}`). Opening it
/// runs the lookup again, so the rights shown are always current.
class SavedLookup {
  const SavedLookup({
    required this.id,
    required this.title,
    required this.lat,
    required this.lng,
    required this.savedAt,
    this.note = '',
    this.state = '',
    this.parcelId = '',
    this.rightNumbers = const [],
  });

  final String id;
  final String title;
  final String note;
  final double lat;
  final double lng;
  final String state;
  final String parcelId;

  /// The rights found when it was saved (to spot changes later).
  final List<String> rightNumbers;
  final DateTime savedAt;

  factory SavedLookup.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return SavedLookup(
      id: doc.id,
      title: d['title'] as String? ?? 'Saved lookup',
      note: d['note'] as String? ?? '',
      lat: (d['lat'] as num?)?.toDouble() ?? 0,
      lng: (d['lng'] as num?)?.toDouble() ?? 0,
      state: d['state'] as String? ?? '',
      parcelId: d['parcelId'] as String? ?? '',
      rightNumbers: [
        for (final r in d['rightNumbers'] as List? ?? const []) '$r',
      ],
      savedAt: (d['savedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

class SavedLookups {
  SavedLookups._();
  static final instance = SavedLookups._();

  CollectionReference<Map<String, dynamic>>? get _col {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('saved');
  }

  Stream<List<SavedLookup>> watch() {
    final col = _col;
    if (col == null) return Stream.value(const []);
    return col
        .orderBy('savedAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(SavedLookup.fromDoc).toList());
  }

  /// A sensible default name for [result]: the address, else the parcel,
  /// else the coordinates.
  static String suggestedTitle(LookupResult result) {
    final info = result.parcelInfo;
    if (info?.address != null) return info!.displayAddress;
    if (info != null && info.parcelId.isNotEmpty) {
      return 'Parcel ${info.parcelId}';
    }
    final a = result.address;
    if (a != null && a.isNotEmpty) return a;
    return '${result.lat?.toStringAsFixed(5)}, '
        '${result.lng?.toStringAsFixed(5)}';
  }

  Future<void> save(
    LookupResult result, {
    required String title,
    String note = '',
  }) async {
    final col = _col;
    if (col == null || result.lat == null || result.lng == null) return;
    await col.add({
      'title': title.trim().isEmpty ? suggestedTitle(result) : title.trim(),
      'note': note.trim(),
      'lat': result.lat,
      'lng': result.lng,
      'state': result.parcelInfo?.state ?? result.stateCode ?? '',
      'parcelId': result.parcelInfo?.parcelId ?? '',
      'rightNumbers': [
        for (final r in result.rights)
          if (r.rightNumber.isNotEmpty) r.rightNumber,
      ],
      'savedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> update(String id, {required String title, String? note}) async {
    await _col?.doc(id).update({
      'title': title.trim(),
      if (note != null) 'note': note.trim(),
    });
  }

  Future<void> delete(String id) async => _col?.doc(id).delete();
}
