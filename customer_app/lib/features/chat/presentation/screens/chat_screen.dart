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
      final response = await ref.read(apiClientProvider).post('/chat/${widget.networkId}', data: {'message': text});
      
      if (response.data['success'] == true) {
        _ctrl.clear();
        ref.invalidate(chatMessagesProvider(widget.networkId));
      } else {
        if (mounted) {
          final message = response.data['message']?.toString() ?? 'تعذر إرسال الرسالة';
          if (_isOutsideDirectorateMessage(message)) {
            _showModernDirectorateWarning(context, message);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(message), backgroundColor: AppColors.accent),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        final errorMessage = e.toString();
        if (_isOutsideDirectorateMessage(errorMessage)) {
          _showModernDirectorateWarning(context, 'لا يمكنك مراسلة شبكة خارج مديريتك المختارة');
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.accent),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showModernDirectorateWarning(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.location_off_rounded, color: AppColors.accent, size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'تنبيه',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.inputBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'يمكنك التواصل مع الشبكات داخل مديرية فقط',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        color: AppColors.textGray,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(
              'فهمت',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isOutsideDirectorateMessage(String message) {
    final lowered = message.toLowerCase();
    return lowered.contains('خارج') ||
        lowered.contains('مديريتك') ||
        lowered.contains('مديرية') ||
        lowered.contains('outside') ||
        lowered.contains('directorate');
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
      final response = await ref.read(apiClientProvider).post('/chat/${widget.networkId}', data: formData);
      
      if (response.data['success'] == true) {
        _ctrl.clear();
        ref.invalidate(chatMessagesProvider(widget.networkId));
      } else {
        if (mounted) {
          final message = response.data['message']?.toString() ?? 'تعذر إرسال الصورة';
          if (_isOutsideDirectorateMessage(message)) {
            _showModernDirectorateWarning(context, message);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(message), backgroundColor: AppColors.accent),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        final errorMessage = e.toString();
        if (_isOutsideDirectorateMessage(errorMessage)) {
          _showModernDirectorateWarning(context, 'لا يمكنك مراسلة شبكة خارج مديريتك المختارة');
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تعذر إرسال الصورة: $e'), backgroundColor: AppColors.accent),
          );
        }
      }
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
