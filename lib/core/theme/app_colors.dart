import 'package:flutter/material.dart';

/// Design tokens cho MicroArt.
/// Mọi giá trị màu trong app PHẢI lấy từ đây, không hardcode hex ở nơi khác.
class AppColors {
  AppColors._();

  // Brand
  static const Color primary = Color(0xFF1A237E); // navy
  static const Color accent = Color(0xFF2E9E6D); // emerald dịu — FAB + trạng thái sẵn sàng + REAL

  // Semantic — kết quả nhận diện
  static const Color real = accent;
  static const Color fake = Color(0xFFC62828);

  // Nền
  static const Color bgLight = Color(0xFFFAFAFA);
  static const Color bgDark = Color(0xFF0F1117);
  static const Color appBarDark = Color(0xFF161B38);

  // Chữ — light mode
  static const Color textPrimaryLight = Color(0xFF1A1F3B);
  static const Color textSecondaryLight = Color(0xFF5C6280);

  // Chữ — dark mode
  static const Color textPrimaryDark = Color(0xFFF2F3F7);
  static const Color textSecondaryDark = Color(0xFFA6ABC4);

  // Bề mặt (card, sheet, popup)
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF171A24);

  // Đường viền / chia mục (dùng cho timeline trong History)
  static const Color dividerLight = Color(0xFFE2E4EE);
  static const Color dividerDark = Color(0xFF2A2E3D);

  // --- Alias tương thích ngược cho code cũ (guide/history/notifications/
  // recognition_screen) — TODO: đổi các file đó sang tên chuẩn ở trên,
  // và sang bản theme-aware (Theme.of(context)...) thay vì static color,
  // vì các alias dưới đây KHÔNG tự đổi theo dark/light mode.
  static const Color navy = primary;
  static const Color green = accent;
  static const Color success = real;
  static const Color danger = fake;
  static const Color textSecondary = textSecondaryLight;
  static const Color border = dividerLight;
}

/// Spacing scale cố định — không dùng giá trị ngoài danh sách này.
class AppSpacing {
  AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

/// Radius scale cố định.
class AppRadius {
  AppRadius._();
  static const double sharp = 0; // timeline line, divider
  static const double sm = 4; // chip trạng thái REAL/FAKE
  static const double md = 8; // nút, input
  static const double lg = 16; // overlay popup kết quả — lớp nổi trên cùng
}