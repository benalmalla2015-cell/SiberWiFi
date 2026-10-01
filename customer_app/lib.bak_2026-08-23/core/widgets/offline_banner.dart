import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/connectivity_service.dart';

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: ConnectivityService.statusChanges,
      initialData: true,
      builder: (context, snapshot) {
        if (snapshot.data != false) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          color: AppColors.accent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          child: const SafeArea(
            bottom: false,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.cloud_off_rounded, color: Colors.white, size: 17),
                SizedBox(width: 8),
                Text('أنت الآن دون اتصال، يتم عرض البيانات المحفوظة', style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 12)),
              ],
            ),
          ),
        );
      },
    );
  }
}
