import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/cache/hive_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/chat_provider.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final int networkId;
  final String networkName;
  const ChatScreen({super.key, required this.networkId, required this.networkName});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _ctrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _loading = true);
    try {
      await ref.read(apiClientProvider).post('/chat/${widget.networkId}', data: {'message': text});
      _ctrl.clear();
      ref.invalidate(chatMessagesProvider(widget.networkId));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.accent));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickAndSendImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;
    setState(() => _loading = true);
    try {
      final formData = FormData.fromMap({
        if (_ctrl.text.trim().isNotEmpty) 'message': _ctrl.text.trim(),
        'image': await MultipartFile.fromFile(picked.path, filename: picked.name),
      });
      await ref.read(apiClientProvider).post('/chat/${widget.networkId}', data: formData);
      _ctrl.clear();
      ref.invalidate(chatMessagesProvider(widget.networkId));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إرسال الصورة: $e'), backgroundColor: AppColors.accent));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(chatMessagesProvider(widget.networkId));

    return Scaffold(
      backgroundColor: AppColors.inputBg,
      appBar: AppBar(
        title: Text('تواصل مع ${widget.networkName}', style: const TextStyle(fontFamily: 'Cairo', fontSize: 16)),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: AppColors.inputBg,
              child: messagesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
                error: (e, _) => Center(child: Text('خطأ: $e')),
                data: (messages) {
                  if (messages.isEmpty) {
                    return const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.chat_bubble_outline_rounded, size: 56, color: AppColors.textLight),
                          SizedBox(height: 12),
                          Text('ابدأ المحادثة بإرسال رسالة', style: TextStyle(fontFamily: 'Cairo', color: AppColors.textGray)),
                        ],
                      ),
                    );
                  }
                  final currentUser = HiveService.getUser();
                  final currentUserId = currentUser?.id;
                  return ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (_, i) {
                      final m = messages[messages.length - 1 - i];
                      final isMe = m['sender_id'] == currentUserId;
                      return _Bubble(
                        text: m['message'] ?? '',
                        imageUrl: m['image_url']?.toString(),
                        isMe: isMe,
                      );
                    },
                  );
                },
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)]),
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    onPressed: _loading ? null : _pickAndSendImage,
                    icon: const Icon(Icons.image_outlined, color: AppColors.primary),
                    tooltip: 'إرسال صورة',
                  ),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      textDirection: TextDirection.rtl,
                      decoration: InputDecoration(
                        hintText: 'اكتب رسالتك...',
                        hintStyle: const TextStyle(fontFamily: 'Cairo'),
                        filled: true,
                        fillColor: AppColors.inputBg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: _loading ? null : _send,
                    icon: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send, color: AppColors.primary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final String text;
  final String? imageUrl;
  final bool isMe;
  const _Bubble({required this.text, required this.imageUrl, required this.isMe});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? AppColors.primary : AppColors.inputBg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (imageUrl != null && imageUrl!.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  imageUrl!,
                  width: 250,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(width: 250, height: 120, child: Center(child: Icon(Icons.broken_image_outlined))),
                ),
              ),
            if (imageUrl != null && imageUrl!.isNotEmpty && text.isNotEmpty) const SizedBox(height: 8),
            if (text.isNotEmpty)
              Text(
                text,
                textDirection: TextDirection.rtl,
                style: TextStyle(fontFamily: 'Cairo', color: isMe ? Colors.white : AppColors.textDark),
              ),
          ],
        ),
      ),
    );
  }
}
