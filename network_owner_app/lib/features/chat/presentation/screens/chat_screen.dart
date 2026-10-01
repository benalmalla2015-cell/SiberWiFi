import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/chat_repository.dart';
import '../providers/chat_provider.dart';

class NetworkOwnerChatScreen extends ConsumerStatefulWidget {
  final int networkId;
  final int contactId;
  final String networkName;
  final String contactName;

  const NetworkOwnerChatScreen({
    super.key,
    required this.networkId,
    required this.contactId,
    required this.networkName,
    required this.contactName,
  });

  @override
  ConsumerState<NetworkOwnerChatScreen> createState() => _NetworkOwnerChatScreenState();
}

class _NetworkOwnerChatScreenState extends ConsumerState<NetworkOwnerChatScreen> {
  final _controller = TextEditingController();
  File? _selectedImage;
  bool _isSending = false;

  ConversationKey get _key => ConversationKey(networkId: widget.networkId, contactId: widget.contactId);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1600);
    if (image != null && mounted) setState(() => _selectedImage = File(image.path));
  }

  Future<void> _send() async {
    final message = _controller.text.trim();
    if ((message.isEmpty && _selectedImage == null) || _isSending) return;

    setState(() => _isSending = true);
    try {
      await ref.read(chatRepositoryProvider).sendMessage(
            networkId: widget.networkId,
            receiverId: widget.contactId,
            message: message,
            imagePath: _selectedImage?.path,
          );
      _controller.clear();
      setState(() => _selectedImage = null);
      ref.invalidate(chatMessagesProvider(_key));
      ref.invalidate(conversationsProvider);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر إرسال الرسالة: $error'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatMessagesProvider(_key));

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.contactName, style: const TextStyle(fontSize: 16)),
            Text(widget.networkName, style: const TextStyle(fontSize: 10, color: Colors.white70)),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(chatMessagesProvider(_key)),
              child: messages.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [const SizedBox(height: 220), Center(child: Text('تعذر تحميل المحادثة: $error'))],
                ),
                data: (items) {
                  if (items.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [SizedBox(height: 220), Center(child: Text('ابدأ المحادثة مع العميل', style: TextStyle(color: AppColors.textGray)))],
                    );
                  }
                  return ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    itemBuilder: (_, index) {
                      final message = items[items.length - index - 1];
                      final isMine = message['sender_id'] is int && message['sender_id'] != widget.contactId;
                      return _MessageBubble(
                        message: message['message']?.toString() ?? '',
                        imageUrl: message['image_url']?.toString(),
                        timestamp: message['created_at']?.toString() ?? '',
                        isMine: isMine,
                      );
                    },
                  );
                },
              ),
            ),
          ),
          _Composer(
            controller: _controller,
            selectedImage: _selectedImage,
            isSending: _isSending,
            onPickImage: _pickImage,
            onRemoveImage: () => setState(() => _selectedImage = null),
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final String message;
  final String? imageUrl;
  final String timestamp;
  final bool isMine;

  const _MessageBubble({required this.message, required this.imageUrl, required this.timestamp, required this.isMine});

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: isMine ? AppColors.primary : AppColors.inputBg, borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (hasImage)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  imageUrl!,
                  width: 260,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(width: 260, height: 120, child: Center(child: Icon(Icons.broken_image_outlined))),
                ),
              ),
            if (hasImage && message.isNotEmpty) const SizedBox(height: 8),
            if (message.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(message, textDirection: TextDirection.rtl, style: TextStyle(color: isMine ? Colors.white : AppColors.textDark)),
              ),
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(timestamp.length >= 16 ? timestamp.substring(11, 16) : timestamp, style: TextStyle(fontSize: 9, color: isMine ? Colors.white70 : AppColors.textGray)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final File? selectedImage;
  final bool isSending;
  final VoidCallback onPickImage;
  final VoidCallback onRemoveImage;
  final VoidCallback onSend;

  const _Composer({
    required this.controller,
    required this.selectedImage,
    required this.isSending,
    required this.onPickImage,
    required this.onRemoveImage,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8)]),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selectedImage != null)
              Align(
                alignment: Alignment.centerRight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.file(selectedImage!, width: 76, height: 76, fit: BoxFit.cover)),
                    Positioned(
                      top: -8,
                      right: -8,
                      child: InkWell(
                        onTap: onRemoveImage,
                        child: const CircleAvatar(radius: 12, backgroundColor: AppColors.error, child: Icon(Icons.close, color: Colors.white, size: 15)),
                      ),
                    ),
                  ],
                ),
              ),
            if (selectedImage != null) const SizedBox(height: 10),
            Row(
              children: [
                SizedBox(
                  width: 48,
                  height: 48,
                  child: IconButton(
                    onPressed: isSending ? null : onPickImage,
                    tooltip: 'إضافة صورة',
                    style: IconButton.styleFrom(backgroundColor: AppColors.primary.withValues(alpha: 0.1), foregroundColor: AppColors.primary),
                    icon: const Icon(Icons.image_outlined),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: controller,
                    maxLength: 5000,
                    minLines: 1,
                    maxLines: 4,
                    textDirection: TextDirection.rtl,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(hintText: 'اكتب ردك للعميل...', counterText: ''),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 52,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: isSending ? null : onSend,
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, padding: EdgeInsets.zero, shape: const CircleBorder()),
                    child: isSending
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.send_rounded),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
