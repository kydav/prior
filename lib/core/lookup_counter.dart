import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LookupCounter {
  static const freeLimit = 5;

  static String _currentMonth() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  static DocumentReference<Map<String, dynamic>>? _docRef() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('usage')
        .doc('lookup_counter');
  }

  static Future<int> getCount() async {
    final docRef = _docRef();
    if (docRef == null) return 0;

    final month = _currentMonth();
    final snapshot = await docRef.get();
    final data = snapshot.data();
    final storedMonth = data?['month'] as String?;
    final count = data?['count'] as int? ?? 0;

    if (storedMonth != month) {
      await docRef.set({
        'month': month,
        'count': 0,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return 0;
    }

    return count;
  }

  static Future<void> increment() async {
    final docRef = _docRef();
    if (docRef == null) return;

    final month = _currentMonth();

    await FirebaseFirestore.instance.runTransaction((txn) async {
      final snapshot = await txn.get(docRef);
      final data = snapshot.data();
      final storedMonth = data?['month'] as String?;
      final current = data?['count'] as int? ?? 0;

      final nextCount = storedMonth == month ? current + 1 : 1;
      txn.set(docRef, {
        'month': month,
        'count': nextCount,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }
}
