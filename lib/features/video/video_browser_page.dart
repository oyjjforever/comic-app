import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/state/app_state.dart';
import '../../core/models/file_info.dart';
import '../../core/services/video_thumbnail_service.dart';
import 'video_player_page.dart';

class VideoBrowserPage extends StatefulWidget {
  const VideoBrowserPage({super.key});

  @override
  State<VideoBrowserPage> createState() => _VideoBrowserPageState();
}

class _VideoBrowserPageState extends State<VideoBrowserPage> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialData();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final appState = context.read<AppState>();
    final videoPath = appState.connectedServer?.videoResourcePath;
    if (videoPath != null && videoPath.isNotEmpty) {
      await appState.loadVideoTreeRoot(videoPath);
    }
    await appState.loadVideoFavorites();
  }

  void _openPlayer(FileInfo file) {
    final appState = context.read<AppState>();
    appState.recordVideoBrowseHistory(file.fullPath);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerPage(
          videoFile: file,
          baseUrl: appState.apiClient!.baseUrl,
        ),
      ),
    );
  }

  List<FileInfo> _getDisplayVideos(AppState appState) {
    switch (appState.videoViewMode) {
      case VideoViewMode.folders:
        return appState.videoFiles;
      case VideoViewMode.favorites:
        return appState.videoFavoriteFiles;
      case VideoViewMode.history:
        return appState.videoBrowseHistoryFiles;
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final screenWidth = MediaQuery.of(context).size.width;
    final isWideScreen = screenWidth >= 840;
    final videoPath = appState.connectedServer?.videoResourcePath;
    final hasVideoPath = videoPath != null && videoPath.isNotEmpty;

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('Video'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () {
            if (isWideScreen) {
              appState.toggleSidebar();
            } else {
              _scaffoldKey.currentState?.openDrawer();
            }
          },
          tooltip: 'Menu',
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: _buildViewModeTabs(appState),
        ),
      ),
      drawer: isWideScreen ? null : _buildDrawer(appState),
      body: !hasVideoPath
          ? _buildNoVideoPathMessage()
          : isWideScreen
              ? _buildWideLayout(appState)
              : _buildNarrowLayout(appState),
    );
  }

  Widget _buildNoVideoPathMessage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.video_library_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'Video directory not configured',
            style: TextStyle(color: Colors.grey[600], fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'Please set the video resource path in the desktop app settings',
            style: TextStyle(color: Colors.grey[500], fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildViewModeTabs(AppState appState) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 600;

    if (isCompact) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            _buildCompactTab(
              icon: Icons.folder,
              label: '本地目录',
              isSelected: appState.videoViewMode == VideoViewMode.folders,
              onTap: () => appState.setVideoViewMode(VideoViewMode.folders),
            ),
            _buildCompactTab(
              icon: Icons.favorite,
              label: '我的收藏',
              isSelected: appState.videoViewMode == VideoViewMode.favorites,
              onTap: () => appState.setVideoViewMode(VideoViewMode.favorites),
            ),
            _buildCompactTab(
              icon: Icons.history,
              label: '浏览历史',
              isSelected: appState.videoViewMode == VideoViewMode.history,
              onTap: () => appState.setVideoViewMode(VideoViewMode.history),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: SegmentedButton<VideoViewMode>(
        segments: const [
          ButtonSegment<VideoViewMode>(
            value: VideoViewMode.folders,
            label: Text('本地目录'),
            icon: Icon(Icons.folder),
          ),
          ButtonSegment<VideoViewMode>(
            value: VideoViewMode.favorites,
            label: Text('我的收藏'),
            icon: Icon(Icons.favorite),
          ),
          ButtonSegment<VideoViewMode>(
            value: VideoViewMode.history,
            label: Text('浏览历史'),
            icon: Icon(Icons.history),
          ),
        ],
        selected: {appState.videoViewMode},
        onSelectionChanged: (mode) {
          appState.setVideoViewMode(mode.first);
        },
      ),
    );
  }

  Widget _buildCompactTab({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? Theme.of(context).colorScheme.secondaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected
                    ? Theme.of(context).colorScheme.onSecondaryContainer
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: isSelected
                      ? Theme.of(context).colorScheme.onSecondaryContainer
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDrawer(AppState appState) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Video Folders',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: appState.isVideoTreeLoading
                  ? const Center(child: CircularProgressIndicator())
                  : appState.videoTreeNodes.isEmpty
                      ? Center(
                          child: Text(
                            'No folders found',
                            style: TextStyle(color: Colors.grey[500]),
                          ),
                        )
                      : ListView.builder(
                          itemCount: appState.videoTreeNodes.length,
                          itemBuilder: (context, index) {
                            return _DrawerVideoTreeNode(
                              node: appState.videoTreeNodes[index],
                              level: 0,
                              onClose: () => Navigator.of(context).pop(),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWideLayout(AppState appState) {
    return Row(
      children: [
        if (appState.videoViewMode == VideoViewMode.folders &&
            appState.isSidebarExpanded)
          SizedBox(
            width: 280,
            child: _VideoFolderTreeSidebar(),
          ),
        Expanded(child: _buildMainContent(appState)),
      ],
    );
  }

  Widget _buildNarrowLayout(AppState appState) {
    return _buildMainContent(appState);
  }

  Widget _buildMainContent(AppState appState) {
    final videos = _getDisplayVideos(appState);

    if (appState.isLoading && videos.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (videos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.movie_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _getEmptyMessage(appState.videoViewMode),
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _refresh(appState),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final crossAxisCount = constraints.maxWidth > 600 ? 4 : 3;
          return GridView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(8),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: 0.75,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: videos.length,
            addAutomaticKeepAlives: false,
            addRepaintBoundaries: true,
            itemBuilder: (context, index) {
              return _VideoCard(
                file: videos[index],
                onTap: () => _openPlayer(videos[index]),
                onLongPress: () =>
                    _showVideoContextMenu(context, videos[index]),
                baseUrl: appState.apiClient!.baseUrl,
              );
            },
          );
        },
      ),
    );
  }

  String _getEmptyMessage(VideoViewMode mode) {
    switch (mode) {
      case VideoViewMode.folders:
        return 'Select a folder from the tree to browse videos';
      case VideoViewMode.favorites:
        return 'No favorite videos yet. Long press to add.';
      case VideoViewMode.history:
        return 'No video browse history yet';
    }
  }

  Future<void> _refresh(AppState appState) async {
    switch (appState.videoViewMode) {
      case VideoViewMode.folders:
        if (appState.selectedVideoTreePath != null) {
          await appState.loadVideoFiles(appState.selectedVideoTreePath!);
        }
        break;
      case VideoViewMode.favorites:
        await appState.loadVideoFavorites();
        break;
      case VideoViewMode.history:
        await appState.loadVideoBrowseHistory();
        break;
    }
  }

  void _showVideoContextMenu(BuildContext context, FileInfo file) {
    final appState = context.read<AppState>();
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.favorite_border),
                title: const Text('Toggle Favorite'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await appState.toggleVideoFavorite(file.fullPath);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Favorite toggled')),
                    );
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Drawer tree node for video folder browsing
class _DrawerVideoTreeNode extends StatefulWidget {
  final FolderTreeNode node;
  final int level;
  final VoidCallback onClose;

  const _DrawerVideoTreeNode({
    required this.node,
    required this.level,
    required this.onClose,
  });

  @override
  State<_DrawerVideoTreeNode> createState() => _DrawerVideoTreeNodeState();
}

class _DrawerVideoTreeNodeState extends State<_DrawerVideoTreeNode> {
  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isSelected =
        appState.selectedVideoTreePath == widget.node.fullPath;
    final hasChildren = !widget.node.isLeaf;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.only(
            left: 8.0 + (widget.level * 16.0),
            right: 8,
          ),
          selected: isSelected,
          leading: hasChildren
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: widget.node.isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(4),
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        )
                      : Icon(
                          widget.node.isExpanded
                              ? Icons.expand_more
                              : Icons.chevron_right,
                          size: 18,
                        ),
                )
              : const Icon(Icons.videocam, size: 18),
          title: Text(
            widget.node.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
          onTap: () {
            if (hasChildren) {
              setState(() {
                widget.node.isExpanded = !widget.node.isExpanded;
              });
              if (widget.node.isExpanded && widget.node.children.isEmpty) {
                appState.loadVideoTreeChildren(widget.node);
              }
            }
            appState.selectVideoTreeNode(widget.node.fullPath);
            widget.onClose();
          },
        ),
        if (widget.node.isExpanded && widget.node.children.isNotEmpty)
          ...widget.node.children.map(
            (child) => _DrawerVideoTreeNode(
              node: child,
              level: widget.level + 1,
              onClose: widget.onClose,
            ),
          ),
      ],
    );
  }
}

/// Video folder tree sidebar for wide layout
class _VideoFolderTreeSidebar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final nodes = appState.videoTreeNodes;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.video_library, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Video Folders',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: appState.isVideoTreeLoading && nodes.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : nodes.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            'No folders found',
                            style: TextStyle(color: Colors.grey[500]),
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(top: 4),
                        itemCount: nodes.length,
                        itemBuilder: (context, index) {
                          return _SidebarTreeNode(
                              node: nodes[index], level: 0);
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _SidebarTreeNode extends StatefulWidget {
  final FolderTreeNode node;
  final int level;

  const _SidebarTreeNode({required this.node, required this.level});

  @override
  State<_SidebarTreeNode> createState() => _SidebarTreeNodeState();
}

class _SidebarTreeNodeState extends State<_SidebarTreeNode> {
  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isSelected =
        appState.selectedVideoTreePath == widget.node.fullPath;
    final hasChildren = !widget.node.isLeaf;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => _onTap(context),
          child: Container(
            padding: EdgeInsets.only(
              left: 8.0 + (widget.level * 16.0),
              right: 8,
              top: 6,
              bottom: 6,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? Theme.of(context).colorScheme.primaryContainer
                  : null,
            ),
            child: Row(
              children: [
                if (hasChildren)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: widget.node.isLoading
                        ? const Padding(
                            padding: EdgeInsets.all(4),
                            child: CircularProgressIndicator(strokeWidth: 1.5),
                          )
                        : Icon(
                            widget.node.isExpanded
                                ? Icons.expand_more
                                : Icons.chevron_right,
                            size: 18,
                          ),
                  )
                else
                  const SizedBox(width: 20),
                const SizedBox(width: 4),
                Icon(
                  widget.node.isExpanded && hasChildren
                      ? Icons.folder_open
                      : Icons.folder,
                  size: 18,
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).iconTheme.color,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.node.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (widget.node.isExpanded && widget.node.children.isNotEmpty)
          ...widget.node.children.map(
            (child) =>
                _SidebarTreeNode(node: child, level: widget.level + 1),
          ),
      ],
    );
  }

  void _onTap(BuildContext context) {
    final appState = context.read<AppState>();

    if (!widget.node.isLeaf) {
      setState(() {
        widget.node.isExpanded = !widget.node.isExpanded;
      });
      if (widget.node.isExpanded && widget.node.children.isEmpty) {
        appState.loadVideoTreeChildren(widget.node);
      }
    }

    appState.selectVideoTreeNode(widget.node.fullPath);
  }
}

/// Video card widget for grid display with client-side thumbnail generation
/// 类似 Electron 端 media-card.vue 的 getVideoThumbnail 方法，
/// 使用原生平台 API 从视频 URL 提取帧作为缩略图
class _VideoCard extends StatefulWidget {
  final FileInfo file;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final String baseUrl;

  const _VideoCard({
    required this.file,
    required this.onTap,
    required this.onLongPress,
    required this.baseUrl,
  });

  @override
  State<_VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<_VideoCard> {
  late Future<Uint8List?> _thumbnailFuture;

  // 使用干净 URL（无查询参数），兼容 Android MediaMetadataRetriever
  String get _videoUrl =>
      '${widget.baseUrl}/api/videofile/${Uri.encodeComponent(widget.file.fullPath)}';

  @override
  void initState() {
    super.initState();
    _thumbnailFuture = VideoThumbnailService.instance.getThumbnail(_videoUrl);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Client-side generated video thumbnail
                  FutureBuilder<Uint8List?>(
                    future: _thumbnailFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return _buildPlaceholder();
                      }
                      if (snapshot.hasData && snapshot.data != null) {
                        return Image.memory(
                          snapshot.data!,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        );
                      }
                      return _buildPlaceholder();
                    },
                  ),
                  // Play icon overlay
                  Center(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(8),
                      child: const Icon(
                        Icons.play_arrow,
                        size: 32,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  // Extension badge
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        widget.file.extension.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  // File size badge
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        widget.file.formattedSize,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              child: Text(
                widget.file.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey[850],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.play_circle_outline,
            size: 48,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              widget.file.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[400],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
