import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

// Set this to your RevenueCat API key from the RC dashboard.
const kRcApiKey = 'REPLACE_WITH_REVENUECAT_API_KEY';

// Must match the entitlement identifier you create in RevenueCat.
const kProEntitlement = 'pro';

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
