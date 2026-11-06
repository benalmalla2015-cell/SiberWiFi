import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/acc_entitlement_provider.dart';
import 'acc_premium_lock_card.dart';

/// Section-level entitlement gate for the accounting domain (ACC-11).
///
/// Wraps a premium section/screen: renders [child] while the feature
/// is allowed, or an [AccPremiumLockCard] once `acc.enforce` is on
/// server-side and the tenant's plan doesn't include [feature].
///
/// While `acc.enforce=0` (the seeded default) this widget is
/// invisible — the same contract the mikrotik FeatureGate shipped
/// with, resolved by the accounting service instead.
///
/// Usage:
/// ```dart
/// AccFeatureGate(
///   feature: AccFeatures.inventory,
///   child: InventoryScreen(),
/// )
/// ```
class AccFeatureGate extends ConsumerWidget {
  const AccFeatureGate({
    super.key,
    required this.feature,
    required this.child,
    this.lockedTitle,
    this.lockedMessage,
  });

  /// One of [AccFeatures] keys.
  final String feature;
  final Widget child;

  /// Optional overrides for the locked-state copy.
  final String? lockedTitle;
  final String? lockedMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowed = ref.watch(accFeatureAllowedProvider(feature));
    if (allowed) return child;
    return AccPremiumLockCard(
      title: lockedTitle,
      message: lockedMessage,
    );
  }
}
