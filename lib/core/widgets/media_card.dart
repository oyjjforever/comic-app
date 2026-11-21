import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 统一媒体卡片（书籍/视频共用）
///
/// 视觉提取自 Electron 版 comic-reader：
/// - 封面铺满 + 底部黑色渐变标题横幅（标题 + 副标题）
/// - 右上角收藏角标；视频卡片中央播放按钮
/// - D-pad 焦点态：橙色描边 + 轻微放大（触屏设备不显示焦点环）
class MediaCard extends StatefulWidget {
  const MediaCard({
    super.key,
    required this.cover,
    required this.title,
    this.subtitle,
    this.isFavorite = false,
    this.showPlayIcon = false,
    this.topStartBadge,
    this.bottomEndBadge,
    this.onTap,
    this.onLongPress,
    this.autofocus = false,
  });

  /// 封面区域内容（图片或占位）
  final Widget cover;

  /// 标题（横幅主行）
  final String title;

  /// 副标题（横幅副行，如页数/大小）
  final String? subtitle;

  /// 是否已收藏（右上角星标）
  final bool isFavorite;

  /// 是否显示中央播放按钮（视频卡片）
  final bool showPlayIcon;

  /// 左上角角标（如视频扩展名）
  final Widget? topStartBadge;

  /// 封面右下角角标（如文件大小）
  final Widget? bottomEndBadge;

  final VoidCallback? onTap;

  final VoidCallback? onLongPress;

  /// 初始焦点（TV 首个卡片）
  final bool autofocus;

  @override
  State<MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends State<MediaCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      onFocusChange: (value) {
        if (_focused != value) {
          setState(() => _focused = value);
        }
      },
      child: AnimatedScale(
        scale: _focused ? 1.04 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: _focused
                ? Border.all(color: AppColors.accent, width: 2.5)
                : null,
            boxShadow: _focused
                ? [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.35),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: widget.onTap,
              onLongPress: widget.onLongPress,
              focusColor: AppColors.accent.withValues(alpha: 0.08),
              hoverColor: Colors.white.withValues(alpha: 0.06),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 封面
                  widget.cover,

                  // 底部标题横幅
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _buildTitleBanner(context),
                  ),

                  // 收藏角标
                  if (widget.isFavorite)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: _buildBadgeContainer(
                        child: const Icon(
                          Icons.bookmark,
                          color: AppColors.accent,
                          size: 16,
                        ),
                      ),
                    ),

                  // 左上角标（视频扩展名等）
                  if (widget.topStartBadge != null)
                    Positioned(top: 6, left: 6, child: widget.topStartBadge!),

                  // 右下角标（文件大小等）
                  if (widget.bottomEndBadge != null)
                    Positioned(
                      right: 6,
                      bottom: null,
                      top: 6,
                      child: widget.bottomEndBadge!,
                    ),

                  // 中央播放按钮
                  if (widget.showPlayIcon)
                    Center(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(10),
                        child: const Icon(
                          Icons.play_arrow,
                          size: 30,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 底部渐变标题横幅：标题 + 副标题
  Widget _buildTitleBanner(BuildContext context) {
    final subtitle = widget.subtitle;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 24, 8, 6),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Color(0xEB000000)],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle != null && subtitle.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
                height: 1.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBadgeContainer({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
      ),
      child: child,
    );
  }
}

/// 小型文本角标（深色底白字，用于扩展名/大小）
class MediaBadge extends StatelessWidget {
  const MediaBadge({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
