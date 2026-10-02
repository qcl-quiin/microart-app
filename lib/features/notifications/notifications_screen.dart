import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/database/database_helper.dart';
import '../../core/models/notification_entry.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<NotificationEntry> _notifs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifs();
  }

  Future<void> _loadNotifs() async {
    final data = await DatabaseHelper.instance.getAllNotifications();
    if (!mounted) return;
    setState(() {
      _notifs = data;
      _loading = false;
    });
  }

  Future<void> _markAllRead() async {
    await DatabaseHelper.instance.markAllNotificationsRead();
    await _loadNotifs();
  }

  Future<void> _onTapNotif(NotificationEntry n) async {
    if (n.id != null && !n.isRead) {
      await DatabaseHelper.instance.markNotificationRead(n.id!);
      await _loadNotifs();
    }
  }

  // TODO: xóa hàm này và nút gọi nó khi Bước 3 (detect thật) xong.
  Future<void> _addMockNotif() async {
    final isReal = DateTime.now().second % 2 == 0;
    await DatabaseHelper.instance.insertNotification(
      NotificationEntry(
        title: isReal ? 'Nhận diện hoàn tất' : 'Cảnh báo',
        body: isReal
            ? 'Kết quả: NGƯỜI THẬT — 92.5%'
            : 'Phát hiện dấu hiệu giả mạo — 85.0%',
        timestamp: DateTime.now(),
      ),
    );
    await _loadNotifs();
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    if (isToday) {
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday = dt.year == yesterday.year && dt.month == yesterday.month && dt.day == yesterday.day;
    if (isYesterday) return 'Hôm qua';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thông báo'),
        actions: [
          // TODO: xóa nút này khi Bước 3 xong
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _addMockNotif,
            tooltip: 'Thêm dữ liệu mẫu (debug)',
          ),
          TextButton(
            onPressed: _markAllRead,
            child: const Text('Đọc tất cả', style: TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notifs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.notifications_none, size: 56, color: AppColors.textSecondary.withValues(alpha: 0.4)),
                      const SizedBox(height: 16),
                      Text('Không có thông báo',
                          style: theme.textTheme.titleMedium?.copyWith(color: AppColors.textSecondary)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _notifs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final n = _notifs[index];
                    final unread = !n.isRead;
                    return Card(
                      child: InkWell(
                        onTap: () => _onTapNotif(n),
                        borderRadius: BorderRadius.circular(8),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: unread ? AppColors.accent.withValues(alpha: 0.12) : AppColors.border,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.notifications,
                              color: unread ? AppColors.accent : AppColors.textSecondary,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            n.title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(n.body, style: theme.textTheme.bodyMedium),
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(_formatTime(n.timestamp), style: theme.textTheme.labelSmall),
                              if (unread) ...[
                                const SizedBox(height: 6),
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: const BoxDecoration(
                                    color: AppColors.accent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}