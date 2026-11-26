import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:prior/core/water_market_client.dart';
import 'package:prior/core/water_rights_client.dart';

/// What a saved item is: a place (a parcel or point looked up on the map) or
/// one water right (from Find water or a right check).
enum SavedKind { place, right }

/// Something the user kept (`users/{uid}/saved/{id}`), with a name and note
/// of their own:
/// - a **place**: where it was and the rights found there then. Opening it
///   runs the lookup again, so the rights shown are always current.
/// - a **right**: its number and a snapshot of what it was when saved (owner,
///   status, quantity). Opening it runs the right check again.
///
/// Docs saved before rights could be saved have no `kind`: they're places.
class SavedLookup {
  const SavedLookup({
    required this.id,
    required this.title,
    required this.lat,
    required this.lng,
    required this.savedAt,
    this.kind = SavedKind.place,
    this.note = '',
    this.state = '',
    this.parcelId = '',
    this.rightNumbers = const [],
    this.rightNumber = '',
    this.owner = '',
    this.status = '',
    this.uses = '',
    this.acreFeet,
  });

  final String id;
  final SavedKind kind;
  final String title;
  final String note;
  final double lat;
  final double lng;
  final String state;
  final String parcelId;

  /// The rights found when it was saved (to spot changes later). Places.
  final List<String> rightNumbers;
  final DateTime savedAt;

  /// A saved right: its number and how it stood when saved.
  final String rightNumber;
  final String owner;
  final String status;
  final String uses;
  final double? acreFeet;

  bool get isRight => kind == SavedKind.right;

  factory SavedLookup.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return SavedLookup(
      id: doc.id,
      kind: d['kind'] == 'right' ? SavedKind.right : SavedKind.place,
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
      rightNumber: d['rightNumber'] as String? ?? '',
      owner: d['owner'] as String? ?? '',
      status: d['status'] as String? ?? '',
      uses: d['uses'] as String? ?? '',
      acreFeet: (d['acreFeet'] as num?)?.toDouble(),
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

  /// A default name for a saved right: its number and holder.
  static String suggestedRightTitle(AreaRight right) => right.owner.isEmpty
      ? 'Right ${right.number}'
      : '${right.number} · ${right.owner}';

  /// Keeps one water right. Its point of diversion is stored as where it is,
  /// so the map can show it later.
  Future<void> saveRight(
    AreaRight right, {
    required String title,
    String note = '',
  }) async {
    final col = _col;
    if (col == null) return;
    await col.add({
      'kind': 'right',
      'title': title.trim().isEmpty ? suggestedRightTitle(right) : title.trim(),
      'note': note.trim(),
      if (right.lat != null) 'lat': right.lat,
      if (right.lng != null) 'lng': right.lng,
      'state': 'UT',
      'rightNumber': right.number,
      'area': right.area,
      'owner': right.owner,
      'status': right.statusLabel,
      'uses': right.usesLabel,
      if (right.acreFeet != null) 'acreFeet': right.acreFeet,
      'savedAt': FieldValue.serverTimestamp(),
    });
  }

  /// The right numbers the user has saved, live (to show which are saved).
  Stream<Set<String>> watchSavedRights() => watch().map(
    (all) => {
      for (final s in all)
        if (s.isRight && s.rightNumber.isNotEmpty) s.rightNumber,
    },
  );

  /// Un-saves [number] (every copy, if it was saved twice).
  Future<void> deleteRight(String number) async {
    final col = _col;
    if (col == null) return;
    final snap = await col.where('rightNumber', isEqualTo: number).get();
    for (final d in snap.docs) {
      await d.reference.delete();
    }
  }

  Future<void> update(String id, {required String title, String? note}) async {
    await _col?.doc(id).update({
      'title': title.trim(),
      if (note != null) 'note': note.trim(),
    });
  }

  Future<void> delete(String id) async => _col?.doc(id).delete();
}
