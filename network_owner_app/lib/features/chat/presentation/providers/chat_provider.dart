import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/chat_repository.dart';

class ConversationKey {
  final int networkId;
  final int contactId;

  const ConversationKey({required this.networkId, required this.contactId});

  @override
  bool operator ==(Object other) =>
      other is ConversationKey &&
      other.networkId == networkId &&
      other.contactId == contactId;

  @override
  int get hashCode => Object.hash(networkId, contactId);
}

final conversationsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return ref.read(chatRepositoryProvider).getConversations();
});

final chatMessagesProvider = FutureProvider.family<List<Map<String, dynamic>>, ConversationKey>(
  (ref, key) => ref.read(chatRepositoryProvider).getMessages(
        networkId: key.networkId,
        contactId: key.contactId,
      ),
);
