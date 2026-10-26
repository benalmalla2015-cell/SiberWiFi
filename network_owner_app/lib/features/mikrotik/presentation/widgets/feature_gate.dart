import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/entitlement_provider.dart';
import 'premium_lock_card.dart';

/// Section-level entitlement gate.
///
/// Wraps a premium section/screen: renders [child] while the feature is
/// allowed, or a [PremiumLockCard] once subscription enforcement is on
/// and the owner's plan doesn't include [feature].
///
/// Sprint-0: `EntitlementService` allows everything, so this widget is
/// invisible — but every new gated screen must already declare its key
/// so Sprint 9 needs zero screen changes.
///
/// Usage:
/// ```dart
/// FeatureGate(
///   feature: MikroFeatures.firewall,
///   child: FirewallScreen(),
/// )
/// ```
class FeatureGate extends ConsumerWidget {
  const FeatureGate({
    super.key,
    required this.feature,
    required this.child,
    this.lockedTitle,
    this.lockedMessage,
  });

  /// One of [MikroFeatures] keys.
  final String feature;
  final Widget child;

  /// Optional overrides for the locked-state copy.
  final String? lockedTitle;
  final String? lockedMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowed = ref.watch(featureAllowedProvider(feature));
    if (allowed) return child;
    return PremiumLockCard(
      title: lockedTitle,
      message: lockedMessage,
    );
  }
}
