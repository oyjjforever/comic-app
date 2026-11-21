import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/models/folder_info.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/media_card.dart';
import '../../core/widgets/responsive.dart';
import '../reader/comic_reader_page.dart';
import 'widgets/folder_tree_sidebar.dart';

/// 漫画浏览页
/// - 手机：抽屉文件夹树 + 顶栏视图切换
/// - 平板/TV：常驻侧边树 + 自适应封面网格
class BookBrowserPage extends StatefulWidget {
  const BookBrowserPage({super.key});

  @override
  State<BookBrowserPage> createState() => _BookBrowserPageState();
}

class _BookBrowserPageState extends State<BookBrowserPage> {
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
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final appState = context.read<AppState>();
    if (appState.connectedServer?.resourcePath != null &&
        appState.connectedServer!.resourcePath.isNotEmpty) {
      await appState.loadTreeRoot(appState.connectedServer!.resourcePath);
    }
    await appState.loadFavorites();
  }

  /// 滚动加载更多：仅目录模式分页（收藏/历史为固定条数，无需分页）
  void _onScroll() {
    if (_scrollController.position.pixels <
        _scrollController.position.maxScrollExtent - 200) {
      return;
    }
    final appState = context.read<AppState>();
    if (appState.viewMode == ViewMode.folders &&
        appState.hasMore &&
        !appState.isLoading) {
      appState.loadMoreFolders(path: appState.selectedTreePath);
    }
  }

  void _openReader(FolderInfo folder) {
    final appState = context.read<AppState>();
    appState.recordBrowseHistory(folder.fullPath);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ComicReaderPage(folder: folder)),
    );
  }

  List<FolderInfo> _getDisplayFolders(AppState appState) {
    switch (appState.viewMode) {
      case ViewMode.folders:
        return appState.folders;
      case ViewMode.favorites:
        return appState.favoriteFolders;
      case ViewMode.history:
        return appState.browseHistoryFolders;
      case ViewMode.downloads:
        return appState.downloadHistoryFolders;
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final size = windowSizeOf(context);
    final isCompact = size == WindowSize.compact;

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(appState.connectedServer?.name ?? '漫画'),
        leading: isCompact
            ? IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () =>
                    _scaffoldKey.currentState?.openDrawer(),
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
      body: isCompact
          ? _buildMainContent(appState)
          : _buildWideLayout(appState),
    );
  }

  /// 手机抽屉：文件夹树
  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: AppColors.surface,
      width: 300,
      child: SafeArea(
        child: FolderTreeView(
          title: '文件夹',
          onNodeSelected: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  /// 大屏：常驻侧边树（仅目录模式显示）+ 内容区
  Widget _buildWideLayout(AppState appState) {
    final showSidebar =
        appState.viewMode == ViewMode.folders && appState.isSidebarExpanded;
    return Row(
      children: [
        if (showSidebar)
          SizedBox(
            width: 280,
            child: FolderTreeView(title: '文件夹'),
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
      // 小屏：图标+小字等宽分布
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            _buildCompactTab(
              icon: Icons.folder,
              label: '目录',
              isSelected: appState.viewMode == ViewMode.folders,
              onTap: () => appState.setViewMode(ViewMode.folders),
            ),
            _buildCompactTab(
              icon: Icons.favorite,
              label: '收藏',
              isSelected: appState.viewMode == ViewMode.favorites,
              onTap: () => appState.setViewMode(ViewMode.favorites),
            ),
            _buildCompactTab(
              icon: Icons.history,
              label: '历史',
              isSelected: appState.viewMode == ViewMode.history,
              onTap: () => appState.setViewMode(ViewMode.history),
            ),
            _buildCompactTab(
              icon: Icons.download,
              label: '下载',
              isSelected: appState.viewMode == ViewMode.downloads,
              onTap: () => appState.setViewMode(ViewMode.downloads),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: SegmentedButton<ViewMode>(
        segments: const [
          ButtonSegment(
            value: ViewMode.folders,
            label: Text('目录'),
            icon: Icon(Icons.folder),
          ),
          ButtonSegment(
            value: ViewMode.favorites,
            label: Text('收藏'),
            icon: Icon(Icons.favorite),
          ),
          ButtonSegment(
            value: ViewMode.history,
            label: Text('历史'),
            icon: Icon(Icons.history),
          ),
          ButtonSegment(
            value: ViewMode.downloads,
            label: Text('下载'),
            icon: Icon(Icons.download),
          ),
        ],
        selected: {appState.viewMode},
        onSelectionChanged: (mode) {
          appState.setViewMode(mode.first);
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
    final folders = _getDisplayFolders(appState);
    final query = _searchController.text;
    final displayFolders = query.isEmpty
        ? folders
        : folders
              .where((f) => f.name.toLowerCase().contains(query.toLowerCase()))
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
        Expanded(child: _buildGrid(appState, displayFolders)),
      ],
    );
  }

  Widget _buildGrid(AppState appState, List<FolderInfo> folders) {
    if (appState.isLoading && folders.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (folders.isEmpty) {
      final isSearch = _searchController.text.isNotEmpty;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSearch ? Icons.search_off : Icons.folder_off,
              size: 56,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              isSearch ? '没有匹配的结果' : _getEmptyMessage(appState.viewMode),
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
          maxCrossAxisExtent: 240,
          childAspectRatio: 0.68,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: folders.length +
            (appState.viewMode == ViewMode.folders && appState.hasMore ? 1 : 0),
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
        itemBuilder: (context, index) {
          if (index >= folders.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          final folder = folders[index];
          return _buildFolderCard(appState, folder);
        },
      ),
    );
  }

  Widget _buildFolderCard(AppState appState, FolderInfo folder) {
    final baseUrl = appState.apiClient?.baseUrl ?? '';
    final coverUrl =
        folder.coverPath != null && folder.coverPath!.isNotEmpty
        ? '$baseUrl/api/file?path=${Uri.encodeComponent(folder.coverPath!)}'
        : null;

    return MediaCard(
      cover: _buildCover(coverUrl, folder.name),
      title: folder.name,
      subtitle: '${folder.fileCount} 页',
      isFavorite: folder.isBookmarked,
      onTap: () => _openReader(folder),
      onLongPress: () => _showFolderContextMenu(folder),
    );
  }

  Widget _buildCover(String? coverUrl, String name) {
    if (coverUrl != null) {
      return CachedNetworkImage(
        imageUrl: coverUrl,
        fit: BoxFit.cover,
        memCacheWidth: 300,
        placeholder: (_, _) => _buildCoverPlaceholder(name),
        errorWidget: (_, _, _) => _buildCoverPlaceholder(name),
      );
    }
    return _buildCoverPlaceholder(name);
  }

  Widget _buildCoverPlaceholder(String name) {
    return Container(
      color: AppColors.coverPlaceholder,
      padding: const EdgeInsets.all(12),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.menu_book_outlined,
            size: 36,
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 8),
          Text(
            name,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _getEmptyMessage(ViewMode mode) {
    switch (mode) {
      case ViewMode.folders:
        return '从左侧文件夹树选择目录浏览';
      case ViewMode.favorites:
        return '暂无收藏，长按卡片即可收藏';
      case ViewMode.history:
        return '暂无浏览历史';
      case ViewMode.downloads:
        return '暂无下载历史';
    }
  }

  Future<void> _refresh(AppState appState) async {
    switch (appState.viewMode) {
      case ViewMode.folders:
        await appState.loadFolders(path: appState.selectedTreePath);
      case ViewMode.favorites:
        await appState.loadFavorites();
      case ViewMode.history:
        await appState.loadBrowseHistory();
      case ViewMode.downloads:
        await appState.loadDownloadHistory();
    }
  }

  void _showFolderContextMenu(FolderInfo folder) {
    final appState = context.read<AppState>();
    final isHistoryMode = appState.viewMode == ViewMode.history;
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
                  folder.name,
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
                  await appState.toggleFavorite(folder.fullPath);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('收藏状态已更新')),
                    );
                  }
                },
              ),
              if (isHistoryMode)
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('从历史中删除'),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await appState.removeBrowseHistoryByPath(folder.fullPath);
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}
