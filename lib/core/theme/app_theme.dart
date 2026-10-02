import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final bg = isDark ? AppColors.bgDark : AppColors.bgLight;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final divider = isDark ? AppColors.dividerDark : AppColors.dividerLight;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.accent,
      onSecondary: Colors.white,
      error: AppColors.fake,
      onError: Colors.white,
      surface: surface,
      onSurface: textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: bg,
      dividerColor: divider,

      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? AppColors.appBarDark : AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),

      // Type scale — giữ Material default (đã theo tỷ lệ hệ thống sẵn),
      // chỉ gán vai trò + màu theo token.
      textTheme: TextTheme(
        // Dùng cho số % confidence trên popup kết quả — con số nổi bật nhất app.
        displayLarge: TextStyle(
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        // Label REAL / FAKE
        titleMedium: TextStyle(
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        // Nội dung mô tả (description từ API)
        bodyMedium: TextStyle(
          color: textPrimary,
          height: 1.4,
        ),
        bodySmall: TextStyle(
          color: textSecondary,
        ),
        // Timestamp trong History
        labelSmall: TextStyle(
          color: textSecondary,
          fontWeight: FontWeight.w500,
        ),
      ).apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),

      // Chip trạng thái REAL/FAKE dùng radius.sm — set trực tiếp ở widget,
      // đây chỉ khai báo theme mặc định cho Chip nếu dùng ChipTheme.
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        labelStyle: TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        side: BorderSide(color: divider),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.md,
          ),
        ),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        shape: CircleBorder(),
      ),

      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: divider),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),

      bottomAppBarTheme: BottomAppBarThemeData(
        color: surface,
        elevation: 4,
      ),
    );
  }
}