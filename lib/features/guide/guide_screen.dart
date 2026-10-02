import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Hướng dẫn & Cài đặt')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Hướng dẫn sử dụng', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          const _GuideSection(
            icon: Icons.videocam_outlined,
            title: 'Bước 1 — Mở video call',
            body: 'Mở bất kỳ ứng dụng video call nào (Zalo, Zoom, Google Meet...) và bắt đầu cuộc gọi.',
          ),
          const SizedBox(height: 10),
          const _GuideSection(
            icon: Icons.touch_app_outlined,
            title: 'Bước 2 — Kích hoạt nhận diện',
            body: 'Quay lại MicroArt, nhấn "Bắt đầu nhận diện". Cấp quyền overlay và ghi màn hình khi được yêu cầu.',
          ),
          const SizedBox(height: 10),
          const _GuideSection(
            icon: Icons.face_outlined,
            title: 'Bước 3 — Chọn khuôn mặt',
            body: 'Vẽ khung quanh khuôn mặt cần xác thực, hoặc chạm vào khuôn mặt được tự động phát hiện.',
          ),
          const SizedBox(height: 10),
          const _GuideSection(
            icon: Icons.analytics_outlined,
            title: 'Bước 4 — Nhận kết quả',
            body: 'Sau ~10 giây, kết quả hiện ngay trên màn hình: người thật hay giả mạo, kèm % độ tin cậy.',
          ),
          const SizedBox(height: 28),
          Text('Về ứng dụng', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('MicroArt v1.0.0', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Micro-motion Analysis & Response Tracking\nXác thực người thật bằng vi chuyển động khuôn mặt.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _GuideSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _GuideSection({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.navy.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppColors.navy, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(body, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}