import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 应用色彩规范（提取自 Electron 版 comic-reader 设计语言）
class AppColors {
  AppColors._();

  /// 页面背景
  static const Color background = Color(0xFF16141C);

  /// 卡片/面板背景
  static const Color surface = Color(0xFF1E1B26);

  /// 更高层级面板（悬浮栏、侧栏头）
  static const Color surfaceHigh = Color(0xFF262230);

  /// 紫灰主面板色（Electron 主色 #322F3B 系）
  static const Color primaryDim = Color(0xFF322F3B);

  /// 品牌橙（激活/焦点/选中）
  static const Color accent = Color(0xFFFF9205);

  static const Color accentHover = Color(0xFFFFA740);

  /// 正文文字
  static const Color textPrimary = Color(0xFFE8E4F0);

  /// 次要文字
  static const Color textSecondary = Color(0xFF9D97AB);

  /// 分隔线
  static const Color divider = Color(0xFF35313F);

  /// 封面占位底色
  static const Color coverPlaceholder = Color(0xFF1A1A2E);
}

/// 构建深色主题
ThemeData buildAppTheme() {
  final scheme = ColorScheme.dark(
    primary: AppColors.accent,
    onPrimary: Colors.black,
    secondary: AppColors.textSecondary,
    onSecondary: AppColors.textPrimary,
    surface: AppColors.surface,
    onSurface: AppColors.textPrimary,
    surfaceContainerHighest: AppColors.surfaceHigh,
    error: const Color(0xFFFF5252),
    onError: Colors.white,
    outline: AppColors.divider,
    outlineVariant: AppColors.divider,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      systemOverlayStyle: SystemUiOverlayStyle.light,
    ),
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.accent.withValues(alpha: 0.25),
      labelTextStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 11, color: AppColors.textSecondary),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.accent.withValues(alpha: 0.25),
      selectedIconTheme: const IconThemeData(color: AppColors.accent),
      unselectedIconTheme: const IconThemeData(color: AppColors.textSecondary),
      selectedLabelTextStyle: const TextStyle(
        color: AppColors.accent,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelTextStyle: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 12,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.accent;
          }
          return AppColors.surfaceHigh;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.black;
          }
          return AppColors.textSecondary;
        }),
        side: const WidgetStatePropertyAll(
          BorderSide(color: AppColors.divider),
        ),
        visualDensity: VisualDensity.compact,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceHigh,
      hintStyle: const TextStyle(color: AppColors.textSecondary),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: AppColors.textSecondary,
      selectedColor: AppColors.accent,
      selectedTileColor: AppColors.accent.withValues(alpha: 0.12),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.divider, thickness: 1),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surfaceHigh,
      contentTextStyle: const TextStyle(color: AppColors.textPrimary),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.accent,
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: AppColors.accent,
      thumbColor: AppColors.accent,
    ),
  );
}
