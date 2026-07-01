import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prior/core/lookup_counter.dart';
import 'package:prior/core/purchases_service.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> showPaywallSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _PaywallSheet(),
  );
}

class _PaywallSheet extends ConsumerStatefulWidget {
  const _PaywallSheet();

  @override
  ConsumerState<_PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends ConsumerState<_PaywallSheet> {
  Package? _package;
  bool _loadingPackage = true;
  bool _purchasing = false;
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    _loadOffering();
  }

  Future<void> _loadOffering() async {
    try {
      final offerings = await Purchases.getOfferings();
      final pkg = offerings.current?.availablePackages.firstOrNull;
      if (mounted) {
        setState(() {
          _package = pkg;
          _loadingPackage = false;
        });
      }
    } catch (e) {
      debugPrint('RevenueCat error: $e');
      if (mounted) setState(() => _loadingPackage = false);
    }
  }

  Future<void> _purchase() async {
    if (_purchasing || _package == null) return;
    setState(() => _purchasing = true);
    try {
      await Purchases.purchase(PurchaseParams.package(_package!));
      ref.invalidate(isSubscribedProvider);
      if (mounted) Navigator.of(context).pop();
    } on PurchasesErrorCode catch (e) {
      if (e != PurchasesErrorCode.purchaseCancelledError && mounted) {
        _showError('Purchase failed. Please try again.');
      }
    } catch (e) {
      if (mounted && !e.toString().contains('cancelled')) {
        _showError('Purchase failed. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  Future<void> _restore() async {
    if (_restoring) return;
    setState(() => _restoring = true);
    try {
      final info = await Purchases.restorePurchases();
      if (mounted) {
        if (info.entitlements.active.containsKey(kProEntitlement)) {
          ref.invalidate(isSubscribedProvider);
          Navigator.of(context).pop();
        } else {
          _showError('No previous purchase found.');
        }
      }
    } catch (e) {
      if (mounted) _showError('Restore failed. Please try again.');
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final price = _loadingPackage
        ? 'Loading…'
        : (_package?.storeProduct.priceString ?? '\$4.99');

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[600],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),

          Icon(Icons.water_drop_rounded, size: 48, color: cs.primary),
          const SizedBox(height: 16),

          Text(
            'Unlock Prior Pro',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'You\'ve used your ${LookupCounter.freeLimit} free lookups this month.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          ..._features.map(
            (f) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: cs.primary, size: 18),
                  const SizedBox(width: 10),
                  Expanded(child: Text(f)),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Price
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cs.primary.withAlpha(80)),
              color: cs.primary.withAlpha(20),
            ),
            child: Text(
              '$price / month',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Subscription renews automatically monthly. Cancel anytime.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: (_purchasing || _loadingPackage) ? null : _purchase,
              child: _purchasing
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Unlock unlimited lookups'),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _restoring ? null : _restore,
            child: _restoring
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Restore purchases'),
          ),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => launchUrl(
                  Uri.parse('https://auaha.app/prior/terms'),
                  mode: LaunchMode.externalApplication,
                ),
                child: Text(
                  'Terms of Use',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
              Text(
                '·',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => launchUrl(
                  Uri.parse('https://auaha.app/prior/privacy'),
                  mode: LaunchMode.externalApplication,
                ),
                child: Text(
                  'Privacy Policy',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

const _features = [
  'Unlimited lookups every month',
  'Utah & Colorado water rights data',
  'Parcel details, acreage & market value',
  'Tap-to-lookup on the map',
];
