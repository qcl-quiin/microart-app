import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Hướng dẫn')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Cách sử dụng', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          const _GuideSection(
            icon: Icons.videocam_outlined,
            title: 'Bước 1 — Đang gọi video',
            body: 'Gọi video với người cần kiểm tra trên Zalo, Messenger... như bình thường, '
                'rồi thoát ra màn hình chính để mở MicroAct.',
          ),
          const SizedBox(height: 10),
          const _GuideSection(
            icon: Icons.touch_app_outlined,
            title: 'Bước 2 — Bắt đầu nhận diện',
            body: 'Nhấn "Bắt đầu nhận diện", đọc lưu ý và cho phép ghi màn hình. '
                'Lần đầu, app còn xin quyền hiển thị trên các ứng dụng khác.',
          ),
          const SizedBox(height: 10),
          const _GuideSection(
            icon: Icons.face_outlined,
            title: 'Bước 3 — Che mặt của bạn',
            body: 'Quay lại cuộc gọi, phóng to cuộc gọi toàn màn hình. Kéo khung xanh vào đúng khu vực MẶT CỦA BẠN '
                '(camera của bạn trong cuộc gọi), rồi bấm ✓. Hệ thống bỏ qua vùng này và chỉ kiểm tra '
                'khuôn mặt còn lại.',
          ),
          const SizedBox(height: 10),
          const _GuideSection(
            icon: Icons.analytics_outlined,
            title: 'Bước 4 — Giữ yên khoảng 10 giây',
            body: 'KHÔNG chạm vào màn hình trong quá trình đếm ngược. Kết quả hiện ngay trong bong bóng: NGƯỜI THẬT hoặc GIẢ MẠO, '
                'kèm độ chính xác %. Bấm "Xem chi tiết" để xem lại trong mục Lịch sử.',
          ),
          const SizedBox(height: 28),
          Text('Lưu ý', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          const _GuideSection(
            icon: Icons.lightbulb_outline,
            title: 'Ứng dụng giúp gì cho bạn?',
            body: 'MicroAct giúp bạn nhận biết nhanh người trong cuộc gọi video là người thật hay khuôn mặt '
                'bị làm giả (deepfake, ghép mặt). Chỉ cần khoảng 10 giây, không cần cài đặt gì cho người bên kia '
                'và dùng được trên các ứng dụng gọi video như Zalo, Messenger. Hiệu quả nhất khi bên kia chỉ có '
                '1 người, mặt rõ và đủ sáng.',
          ),
          const SizedBox(height: 10),
          const _GuideSection(
            icon: Icons.lock_outline,
            title: 'Quyền riêng tư',
            body: 'MicroAct gửi đoạn video 10 giây vừa ghi lên máy chủ để phân tích. Video chỉ dùng tạm: '
                'được xoá khỏi máy sau khi gửi và máy chủ cũng xoá sau khi phân tích. Ứng dụng không lưu '
                'ảnh hay video nào; chỉ kết quả (thật/giả, độ chính xác, mô tả, thời gian) được lưu trong Lịch sử.',
          ),
          const SizedBox(height: 10),
          const _GuideSection(
            icon: Icons.verified_user_outlined,
            title: 'Cách đọc kết quả',
            body: 'MicroAct phân tích vi chuyển động khuôn mặt trong đoạn video 10 giây và đưa ra xác suất '
                'người thật hoặc giả mạo. Ánh sáng, độ nét và chất lượng mạng của cuộc gọi có thể ảnh hưởng '
                'đến kết quả.',
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
                  Text('MicroAct v1.0.0', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Micro-motion Analysis & Confidence Tracking\nXác thực người thật bằng vi chuyển động khuôn mặt.',
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
