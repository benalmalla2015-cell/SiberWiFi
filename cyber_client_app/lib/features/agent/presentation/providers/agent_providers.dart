import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/agent_api.dart';

/// Agent session state: null = logged out / token dead.
class AgentSession extends Notifier<Map<String, dynamic>?> {
  @override
  Map<String, dynamic>? build() => null;

  void signIn(Map<String, dynamic> profile) => state = profile;
  void signOut() => state = null;
}

final agentSessionProvider =
    NotifierProvider<AgentSession, Map<String, dynamic>?>(AgentSession.new);

/// The role gate: resolves the agent profile when a session exists.
final agentProfileProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  return ref.read(agentApiProvider).profile();
});

/// "أرباحي" — summary + commission ledger (refresh via invalidate).
final agentEarningsProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  return ref.read(agentApiProvider).earnings();
});

/// "سجل عملياتي" — the agent's top-up history.
final agentTopupsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return ref.read(agentApiProvider).topups();
});
