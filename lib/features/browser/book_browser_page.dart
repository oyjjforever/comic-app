import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/state/app_state.dart';
import '../../core/models/folder_info.dart';
import '../reader/comic_reader_page.dart';
import '../discovery/server_discovery_page.dart';
import 'widgets/folder_tree_sidebar.dart';

class BookBrowserPage extends StatefulWidget {
  const BookBrowserPage({super.key});

  @override
  State<BookBrowserPage> createState() => _BookBrowserPageState();
}

class _BookBrowserPageState extends State<BookBrowserPage> {
  final ScrollController _scrollController = ScrollController();

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
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final appState = context.read<AppState>();
    if (appState.connectedServer?.resourcePath != null) {
      await appState.loadTreeRoot(appState.connectedServer!.resourcePath!);
    }
    await appState.loadFavorites();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      final appState = context.read<AppState>();
      if (appState.hasMore && !appState.isLoading) {
        appState.loadMoreFolders(path: appState.selectedTreePath);
      }
    }
  }

  void _openReader(FolderInfo folder) {
    final appState = context.read<AppState>();
    appState.recordBrowseHistory(folder.fullPath);
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ComicReaderPage(folder: folder)));
  }

  void _disconnect() {
    final appState = context.read<AppState>();
    appState.disconnect();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ServerDiscoveryPage()),
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
    final screenWidth = MediaQuery.of(context).size.width;
    final isWideScreen = screenWidth >= 840;

    return Scaffold(
      appBar: AppBar(
        title: Text(appState.connectedServer?.name ?? 'Comic Reader'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () {
            if (isWideScreen) {
              appState.toggleSidebar();
            } else {
              Scaffold.of(context).openDrawer();
            }
          },
          tooltip: 'Menu',
        ),
        actions: [
          _buildViewModeTabs(appState),
          IconButton(
            icon: const Icon(Icons.link_off),
            onPressed: _disconnect,
            tooltip: 'Disconnect',
          ),
        ],
      ),
      drawer: isWideScreen ? null : _buildDrawer(appState),
      body: isWideScreen
          ? _buildWideLayout(appState)
          : _buildNarrowLayout(appState),
    );
  }

  Widget _buildViewModeTabs(AppState appState) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: SegmentedButton<ViewMode>(
          segments: const [
            ButtonSegment<ViewMode>(
              value: ViewMode.folders,
              label: Text('Folders'),
              icon: Icon(Icons.folder),
            ),
            ButtonSegment<ViewMode>(
              value: ViewMode.favorites,
              label: Text('Favorites'),
              icon: Icon(Icons.favorite),
            ),
            ButtonSegment<ViewMode>(
              value: ViewMode.history,
              label: Text('History'),
              icon: Icon(Icons.history),
            ),
            ButtonSegment<ViewMode>(
              value: ViewMode.downloads,
              label: Text('Downloads'),
              icon: Icon(Icons.download),
            ),
          ],
          selected: {appState.viewMode},
          onSelectionChanged: (mode) {
            appState.setViewMode(mode.first);
          },
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
                'Folder Tree',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: appState.isTreeLoading
                  ? const Center(child: CircularProgressIndicator())
                  : appState.treeNodes.isEmpty
                  ? Center(
                      child: Text(
                        'No folders found',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    )
                  : ListView.builder(
                      itemCount: appState.treeNodes.length,
                      itemBuilder: (context, index) {
                        return _DrawerTreeNode(
                          node: appState.treeNodes[index],
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
        if (appState.viewMode == ViewMode.folders && appState.isSidebarExpanded)
          const SizedBox(width: 280, child: FolderTreeSidebar()),
        Expanded(child: _buildMainContent(appState)),
      ],
    );
  }

  Widget _buildNarrowLayout(AppState appState) {
    return _buildMainContent(appState);
  }

  Widget _buildMainContent(AppState appState) {
    final folders = _getDisplayFolders(appState);

    if (appState.isLoading && folders.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (folders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _getEmptyMessage(appState.viewMode),
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _refresh(appState),
      child: GridView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 0.6,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: folders.length + (appState.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= folders.length) {
            return const Center(child: CircularProgressIndicator());
          }
          return _FolderCard(
            folder: folders[index],
            onTap: () => _openReader(folders[index]),
            onLongPress: () => _showFolderContextMenu(context, folders[index]),
            baseUrl: appState.apiClient!.baseUrl,
          );
        },
      ),
    );
  }

  String _getEmptyMessage(ViewMode mode) {
    switch (mode) {
      case ViewMode.folders:
        return 'Select a folder from the tree to browse';
      case ViewMode.favorites:
        return 'No favorites yet. Long press a folder to add.';
      case ViewMode.history:
        return 'No browse history yet';
      case ViewMode.downloads:
        return 'No download history yet';
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

  void _showFolderContextMenu(BuildContext context, FolderInfo folder) {
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
                  await appState.toggleFavorite(folder.fullPath);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Favorite toggled')),
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remove from History'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  // TODO: implement remove from history
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Drawer tree node for phone layout
class _DrawerTreeNode extends StatefulWidget {
  final FolderTreeNode node;
  final int level;
  final VoidCallback onClose;

  const _DrawerTreeNode({
    required this.node,
    required this.level,
    required this.onClose,
  });

  @override
  State<_DrawerTreeNode> createState() => _DrawerTreeNodeState();
}

class _DrawerTreeNodeState extends State<_DrawerTreeNode> {
  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isSelected = appState.selectedTreePath == widget.node.fullPath;
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
              : const Icon(Icons.folder, size: 18),
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
                appState.loadTreeChildren(widget.node);
              }
            }
            appState.selectTreeNode(widget.node.fullPath);
            widget.onClose();
          },
        ),
        if (widget.node.isExpanded && widget.node.children.isNotEmpty)
          ...widget.node.children.map(
            (child) => _DrawerTreeNode(
              node: child,
              level: widget.level + 1,
              onClose: widget.onClose,
            ),
          ),
      ],
    );
  }
}

/// Folder card widget for grid display
class _FolderCard extends StatelessWidget {
  final FolderInfo folder;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final String baseUrl;

  const _FolderCard({
    required this.folder,
    required this.onTap,
    required this.onLongPress,
    required this.baseUrl,
  });

  @override
  Widget build(BuildContext context) {
    final coverUrl = folder.coverPath != null && folder.coverPath!.isNotEmpty
        ? '$baseUrl/api/file?path=${Uri.encodeComponent(folder.coverPath!)}'
        : null;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Cover image
            Expanded(
              child: coverUrl != null
                  ? CachedNetworkImage(
                      imageUrl: coverUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: Colors.grey[200],
                        child: const Center(
                          child: Icon(
                            Icons.folder,
                            size: 40,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: Colors.grey[200],
                        child: const Center(
                          child: Icon(
                            Icons.broken_image,
                            size: 40,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    )
                  : Container(
                      color: Colors.grey[200],
                      child: const Center(
                        child: Icon(Icons.folder, size: 40, color: Colors.grey),
                      ),
                    ),
            ),
            // Info section
            Container(
              padding: const EdgeInsets.all(6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    folder.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        '${folder.fileCount} pages',
                        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                      ),
                      const Spacer(),
                      if (folder.isBookmarked)
                        const Icon(
                          Icons.bookmark,
                          color: Colors.amber,
                          size: 14,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
