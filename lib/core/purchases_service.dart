import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

// Set this to your RevenueCat API key from the RC dashboard.
final kRcApiKey = Platform.isIOS
    ? 'appl_lXKdMxtlGlNOsvgRhTnlfmOYBai'
    : 'goog_RkQurJPKVtihtxjqvYDyfLWXGvd';

// Must match the entitlement identifier you create in RevenueCat.
const kProEntitlement = 'Prior Pro';

Future<void> initPurchases() async {
  final user = FirebaseAuth.instance.currentUser;
  final email = user?.email;
  await Purchases.setLogLevel(kDebugMode ? LogLevel.debug : LogLevel.error);
  await Purchases.configure(PurchasesConfiguration(kRcApiKey));
  if (email != null && email.isNotEmpty) {
    await Purchases.setEmail(email);
  }
  if (user?.displayName != null && user!.displayName!.isNotEmpty) {
    await Purchases.setDisplayName(user.displayName!);
  }
}

final isSubscribedProvider = FutureProvider<bool>((ref) async {
  try {
    final info = await Purchases.getCustomerInfo();
    return info.entitlements.active.containsKey(kProEntitlement);
  } catch (e) {
    debugPrint('RevenueCat error: $e');
    return false;
  }
});
