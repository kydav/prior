import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prior/core/lookup_counter.dart';
import 'package:prior/core/purchases_service.dart';

/// Whether the user may run one more lookup: always for Pro, otherwise while
/// the free monthly count lasts. Spends one free lookup when it says yes.
/// Never throws: if the count can't be read, the lookup is allowed.
Future<bool> spendLookup(WidgetRef ref) async {
  try {
    if (await ref.read(isSubscribedProvider.future)) return true;
    if (await LookupCounter.getCount() >= LookupCounter.freeLimit) {
      return false;
    }
    await LookupCounter.increment();
    return true;
  } catch (e) {
    debugPrint('Lookup gate error: $e');
    return true;
  }
}
