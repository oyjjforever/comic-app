import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/state/app_state.dart';
import '../../../core/theme/app_theme.dart';

/// 文件夹树视图（漫画/视频共用）
///
/// - 侧栏（大屏）与抽屉（手机）两种场景复用
/// - 懒加载子节点（点击展开时请求）
/// - 整树只 watch 一次 AppState（节点不各自订阅，避免无关通知全树重建）
class FolderTreeView extends StatefulWidget {
  const FolderTreeView({
    super.key,
    required this.title,
    this.onNodeSelected,
  });

  /// 侧栏标题
  final String title;

  /// 选中节点后的回调（抽屉场景用于关闭抽屉）
  final VoidCallback? onNodeSelected;

  @override
  State<FolderTreeView> createState() => _FolderTreeViewState();
}

class _FolderTreeViewState extends State<FolderTreeView> {
  @override
  Widget build(BuildContext context) {
    // 单点监听：树节点、选中路径、加载态
    final appState = context.watch<AppState>();
    final nodes = appState.treeNodes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(
            children: [
              const Icon(Icons.folder_open, size: 16),
              const SizedBox(width: 8),
              Text(
                widget.title,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
        Divider(
          height: 1,
          color: Theme.of(context).dividerColor,
        ),
        Expanded(
          child: appState.isTreeLoading && nodes.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : nodes.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      '暂无文件夹',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
              itemCount: nodes.length,
              itemBuilder: (context, index) {
                return _TreeNodeItem(
                  node: nodes[index],
                  level: 0,
                  selectedPath: appState.selectedTreePath,
                  onExpandToggle: _onExpandToggle,
                  onSelect: _onSelect,
                );
              },
            ),
        ),
      ],
    );
  }

  /// 展开/收起（仅箭头区域触发，不改变选中）
  void _onExpandToggle(FolderTreeNode node) {
    final appState = context.read<AppState>();
    setState(() {
      node.isExpanded = !node.isExpanded;
    });
    if (node.isExpanded && node.children.isEmpty) {
      appState.loadTreeChildren(node);
    }
  }

  /// 选中节点并加载内容
  void _onSelect(FolderTreeNode node) {
    context.read<AppState>().selectTreeNode(node.fullPath);
    widget.onNodeSelected?.call();
  }
}

/// 视频文件夹树视图（结构同 FolderTreeView，绑定视频树状态）
class VideoFolderTreeView extends StatefulWidget {
  const VideoFolderTreeView({
    super.key,
    required this.title,
    this.onNodeSelected,
  });

  final String title;
  final VoidCallback? onNodeSelected;

  @override
  State<VideoFolderTreeView> createState() => _VideoFolderTreeViewState();
}

class _VideoFolderTreeViewState extends State<VideoFolderTreeView> {
  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final nodes = appState.videoTreeNodes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(
            children: [
              const Icon(Icons.video_library, size: 16),
              const SizedBox(width: 8),
              Text(
                widget.title,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
        Divider(
          height: 1,
          color: Theme.of(context).dividerColor,
        ),
        Expanded(
          child: appState.isVideoTreeLoading && nodes.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : nodes.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      '暂无文件夹',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
              itemCount: nodes.length,
              itemBuilder: (context, index) {
                return _TreeNodeItem(
                  node: nodes[index],
                  level: 0,
                  selectedPath: appState.selectedVideoTreePath,
                  onExpandToggle: _onExpandToggle,
                  onSelect: _onSelect,
                  isVideo: true,
                );
              },
            ),
        ),
      ],
    );
  }

  /// 展开/收起（仅箭头区域触发，不改变选中）
  void _onExpandToggle(FolderTreeNode node) {
    final appState = context.read<AppState>();
    setState(() {
      node.isExpanded = !node.isExpanded;
    });
    if (node.isExpanded && node.children.isEmpty) {
      appState.loadVideoTreeChildren(node);
    }
  }

  /// 选中节点并加载内容
  void _onSelect(FolderTreeNode node) {
    context.read<AppState>().selectVideoTreeNode(node.fullPath);
    widget.onNodeSelected?.call();
  }
}

/// 树节点行（含递归子节点）
/// - 箭头区域：仅展开/收起
/// - 行其余区域：选中节点
class _TreeNodeItem extends StatelessWidget {
  const _TreeNodeItem({
    required this.node,
    required this.level,
    required this.selectedPath,
    required this.onExpandToggle,
    required this.onSelect,
    this.isVideo = false,
  });

  final FolderTreeNode node;
  final int level;
  final String? selectedPath;
  final void Function(FolderTreeNode node) onExpandToggle;
  final void Function(FolderTreeNode node) onSelect;
  final bool isVideo;

  @override
  Widget build(BuildContext context) {
    final isSelected = selectedPath == node.fullPath;
    final hasChildren = !node.isLeaf;
    final folderIcon = isVideo ? Icons.videocam : Icons.folder;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.only(left: 8.0 + (level * 14.0), right: 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => onSelect(node),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.accent.withValues(alpha: 0.14)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  if (hasChildren)
                    // 展开箭头独立点击区：只展开/收起，不选中
                    SizedBox(
                      width: 18,
                      height: 24,
                      child: InkWell(
                        onTap: () => onExpandToggle(node),
                        borderRadius: BorderRadius.circular(4),
                        child: Center(
                          child: node.isLoading
                              ? const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                  ),
                                )
                              : Icon(
                                  node.isExpanded
                                      ? Icons.expand_more
                                      : Icons.chevron_right,
                                  size: 18,
                                  color: AppColors.textSecondary,
                                ),
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: 18),
                  const SizedBox(width: 6),
                  Icon(
                    hasChildren && node.isExpanded
                        ? Icons.folder_open
                        : folderIcon,
                    size: 16,
                    color: isSelected
                        ? AppColors.accent
                        : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      node.name,
                      style: TextStyle(
                        fontSize: 13,
                        color: isSelected
                            ? AppColors.accent
                            : AppColors.textPrimary,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (node.isExpanded && node.children.isNotEmpty)
          ...node.children.map(
            (child) => _TreeNodeItem(
              node: child,
              level: level + 1,
              selectedPath: selectedPath,
              onExpandToggle: onExpandToggle,
              onSelect: onSelect,
              isVideo: isVideo,
            ),
          ),
      ],
    );
  }
}
