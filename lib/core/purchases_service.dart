import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

// Set this to your RevenueCat API key from the RC dashboard.
final kRcApiKey = Platform.isIOS
    ? 'appl_pWCEVUfkvhcAmjUrkJKPJWDssTH'
    : 'goog_NNTOeRWLDWDDCIVJpqZdoFQGYzM';

// Must match the entitlement identifier you create in RevenueCat.
const kProEntitlement = 'Prior Pro';

Future<void> initPurchases() async {
  await Purchases.setLogLevel(kDebugMode ? LogLevel.debug : LogLevel.error);
  await Purchases.configure(PurchasesConfiguration(kRcApiKey));
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
