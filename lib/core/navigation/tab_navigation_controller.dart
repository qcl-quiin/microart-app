import 'package:flutter/foundation.dart';

/// Cầu nối đơn giản để yêu cầu MainScaffold chuyển tab, và báo cho
/// HistoryScreen biết cần tự mở đúng 1 phiên cụ thể — dùng chung để
/// tránh vòng lặp import giữa các file features/.
class TabNavigationController {
  TabNavigationController._();

  /// 0 = Nhận diện, 1 = Lịch sử, 2 = Thông báo, 3 = Hướng dẫn.
  /// Là nguồn duy nhất quyết định tab hiện tại — cả bottom nav lẫn điều
  /// hướng từ overlay đều ghi vào đây, MainScaffold chỉ lắng nghe.
  static final ValueNotifier<int> requestedTabIndex = ValueNotifier<int>(0);

  /// id của phiên History cần tự mở chi tiết ngay khi vào tab Lịch sử
  /// (đặt bởi RecognitionScreen khi overlay báo 'view_details').
  /// HistoryScreen đọc xong tự set về null để không mở lặp lại.
  static final ValueNotifier<int?> pendingHistoryDetailId = ValueNotifier<int?>(null);
}