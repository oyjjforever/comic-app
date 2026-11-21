import 'package:flutter/material.dart';

/// 窗口尺寸分档（对齐 Material 3 窗口尺寸类）
enum WindowSize {
  /// 手机竖屏 < 600
  compact,

  /// 平板竖屏 600 - 840
  medium,

  /// 平板横屏 / TV >= 840
  expanded,
}

/// 根据宽度取窗口尺寸分档
WindowSize windowSizeOf(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width < 600) return WindowSize.compact;
  if (width < 840) return WindowSize.medium;
  return WindowSize.expanded;
}

/// 是否为可常驻侧边栏的大屏
bool isWideScreen(BuildContext context) =>
    windowSizeOf(context) != WindowSize.compact;
