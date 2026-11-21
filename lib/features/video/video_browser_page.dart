import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/file_info.dart';
import '../../core/services/video_thumbnail_service.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/media_card.dart';
import '../../core/widgets/responsive.dart';
import '../browser/widgets/folder_tree_sidebar.dart';
import 'video_player_page.dart';

/// 视频浏览页
/// - 手机：抽屉文件夹树 + 顶栏视图切换
/// - 平板/TV：常驻侧边树 + 自适应封面网格
class VideoBrowserPage extends StatefulWidget {
  const VideoBrowserPage({super.key});

  @override
  State<VideoBrowserPage> createState() => _VideoBrowserPageState();
}

class _VideoBrowserPageState extends State<VideoBrowserPage> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _searchController = TextEditingController();
  bool _showSearch = false;

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
    _searchController.dispose();
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
    final size = windowSizeOf(context);
    final isCompact = size == WindowSize.compact;
    final videoPath = appState.connectedServer?.videoResourcePath;
    final hasVideoPath = videoPath != null && videoPath.isNotEmpty;

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('视频'),
        leading: isCompact
            ? IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                tooltip: '文件夹',
              )
            : IconButton(
                icon: Icon(
                  appState.isSidebarExpanded
                      ? Icons.view_sidebar_outlined
                      : Icons.view_sidebar,
                ),
                onPressed: appState.toggleSidebar,
                tooltip: '侧边栏',
              ),
        actions: [
          IconButton(
            icon: Icon(_showSearch ? Icons.search_off : Icons.search),
            onPressed: () {
              setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) {
                  _searchController.clear();
                }
              });
            },
            tooltip: '搜索',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: _buildViewModeTabs(appState, isCompact),
        ),
      ),
      drawer: isCompact ? _buildDrawer() : null,
      body: !hasVideoPath
          ? _buildNoVideoPathMessage()
          : isCompact
          ? _buildMainContent(appState)
          : _buildWideLayout(appState),
    );
  }

  Widget _buildNoVideoPathMessage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.video_library_outlined,
            size: 56,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 12),
          const Text(
            '未配置视频目录',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
          ),
          const SizedBox(height: 8),
          const Text(
            '请在电脑端设置中配置视频资源路径',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: AppColors.surface,
      width: 300,
      child: SafeArea(
        child: VideoFolderTreeView(
          title: '视频文件夹',
          onNodeSelected: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  Widget _buildWideLayout(AppState appState) {
    final showSidebar = appState.videoViewMode == VideoViewMode.folders &&
        appState.isSidebarExpanded;
    return Row(
      children: [
        if (showSidebar)
          SizedBox(
            width: 280,
            child: VideoFolderTreeView(title: '视频文件夹'),
          ),
        if (showSidebar)
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: Theme.of(context).dividerColor,
          ),
        Expanded(child: _buildMainContent(appState)),
      ],
    );
  }

  Widget _buildViewModeTabs(AppState appState, bool isCompact) {
    if (isCompact) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            _buildCompactTab(
              icon: Icons.folder,
              label: '目录',
              isSelected: appState.videoViewMode == VideoViewMode.folders,
              onTap: () =>
                  appState.setVideoViewMode(VideoViewMode.folders),
            ),
            _buildCompactTab(
              icon: Icons.favorite,
              label: '收藏',
              isSelected: appState.videoViewMode == VideoViewMode.favorites,
              onTap: () =>
                  appState.setVideoViewMode(VideoViewMode.favorites),
            ),
            _buildCompactTab(
              icon: Icons.history,
              label: '历史',
              isSelected: appState.videoViewMode == VideoViewMode.history,
              onTap: () =>
                  appState.setVideoViewMode(VideoViewMode.history),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: SegmentedButton<VideoViewMode>(
        segments: const [
          ButtonSegment(
            value: VideoViewMode.folders,
            label: Text('目录'),
            icon: Icon(Icons.folder),
          ),
          ButtonSegment(
            value: VideoViewMode.favorites,
            label: Text('收藏'),
            icon: Icon(Icons.favorite),
          ),
          ButtonSegment(
            value: VideoViewMode.history,
            label: Text('历史'),
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
    final color = isSelected ? AppColors.accent : AppColors.textSecondary;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: color,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent(AppState appState) {
    final videos = _getDisplayVideos(appState);
    final query = _searchController.text;
    final displayVideos = query.isEmpty
        ? videos
        : videos
              .where((v) => v.name.toLowerCase().contains(query.toLowerCase()))
              .toList();

    return Column(
      children: [
        if (_showSearch)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: '搜索当前列表...',
                prefixIcon: Icon(Icons.search, size: 20),
                isDense: true,
              ),
            ),
          ),
        Expanded(child: _buildGrid(appState, displayVideos)),
      ],
    );
  }

  Widget _buildGrid(AppState appState, List<FileInfo> videos) {
    if (appState.isLoading && videos.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (videos.isEmpty) {
      final isSearch = _searchController.text.isNotEmpty;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSearch ? Icons.search_off : Icons.movie_outlined,
              size: 56,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              isSearch ? '没有匹配的结果' : _getEmptyMessage(appState.videoViewMode),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _refresh(appState),
      child: GridView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(10),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 280,
          childAspectRatio: 0.78,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: videos.length,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
        itemBuilder: (context, index) {
          return _VideoCard(
            file: videos[index],
            baseUrl: appState.apiClient?.baseUrl ?? '',
            onTap: () => _openPlayer(videos[index]),
            onLongPress: () => _showVideoContextMenu(videos[index]),
          );
        },
      ),
    );
  }

  String _getEmptyMessage(VideoViewMode mode) {
    switch (mode) {
      case VideoViewMode.folders:
        return '从左侧文件夹树选择目录浏览视频';
      case VideoViewMode.favorites:
        return '暂无收藏，长按卡片即可收藏';
      case VideoViewMode.history:
        return '暂无观看历史';
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

  void _showVideoContextMenu(FileInfo file) {
    final appState = context.read<AppState>();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  file.name,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.favorite_border),
                title: const Text('收藏 / 取消收藏'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await appState.toggleVideoFavorite(file.fullPath);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('收藏状态已更新')),
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

/// 视频卡片：客户端生成缩略图（带磁盘/内存缓存），并随文件变化刷新
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
  Future<Uint8List?>? _thumbnailFuture;

  // 使用干净 URL（无查询参数），兼容 Android MediaMetadataRetriever
  String get _videoUrl =>
      '${widget.baseUrl}/api/videofile/${Uri.encodeComponent(widget.file.fullPath)}';

  // 服务器 ffmpeg 封面接口（优先于本地生成）
  String get _serverCoverUrl =>
      '${widget.baseUrl}/api/video-cover?path=${Uri.encodeComponent(widget.file.fullPath)}';

  @override
  void initState() {
    super.initState();
    _thumbnailFuture = VideoThumbnailService.instance.getThumbnail(
      _videoUrl,
      serverCoverUrl: _serverCoverUrl,
    );
  }

  @override
  void didUpdateWidget(covariant _VideoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // GridView 复用 State 时，文件变了必须重新取缩略图，否则显示错图
    if (oldWidget.file.fullPath != widget.file.fullPath) {
      _thumbnailFuture = VideoThumbnailService.instance.getThumbnail(
        _videoUrl,
        serverCoverUrl: _serverCoverUrl,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MediaCard(
      cover: _buildCover(),
      title: widget.file.name,
      subtitle: widget.file.formattedSize,
      showPlayIcon: true,
      topStartBadge: MediaBadge(
        text: widget.file.extension.replaceAll('.', '').toUpperCase(),
      ),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
    );
  }

  Widget _buildCover() {
    return FutureBuilder<Uint8List?>(
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
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: AppColors.coverPlaceholder,
      child: Center(
        child: Icon(
          Icons.play_circle_outline,
          size: 40,
          color: AppColors.textSecondary.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}
