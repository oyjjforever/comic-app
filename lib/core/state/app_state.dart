import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/server_info.dart';
import '../models/folder_info.dart';
import '../models/file_info.dart';
import '../models/favorite_info.dart';
import '../models/history_info.dart';
import '../network/api_client.dart';
import '../network/server_discovery.dart';
import '../services/video_thumbnail_service.dart';

/// 视图模式
enum ViewMode { folders, favorites, history, downloads }

/// 视频视图模式
enum VideoViewMode { folders, favorites, history }

/// 应用全局状态管理
class AppState extends ChangeNotifier {
  static const String _lastServerIpKey = 'last_server_ip';
  static const String _lastServerPortKey = 'last_server_port';

  /// 树顶"已收藏"虚拟分组节点的 fullPath（与 Electron 端 __bookmarked_group__ 一致）
  static const String bookmarkGroupKey = '__bookmarked_group__';

  ServerInfo? _connectedServer;
  ApiClient? _apiClient;
  final ServerDiscovery _discovery = ServerDiscovery();

  // 浏览状态
  List<FolderInfo> _folders = [];
  List<FileInfo> _files = [];
  FolderInfo? _currentFolder;
  bool _isLoading = false;
  String? _errorMessage;

  // 分页
  int _currentPage = 0;
  bool _hasMore = true;
  int _totalFolders = 0;

  // 文件夹树状态
  List<FolderTreeNode> _treeNodes = [];
  String? _selectedTreePath;

  // 视图模式
  ViewMode _viewMode = ViewMode.favorites;

  // 收藏状态
  List<FavoriteInfo> _favorites = [];
  List<FolderInfo> _favoriteFolders = [];

  // 浏览历史状态
  List<HistoryInfo> _browseHistory = [];
  List<FolderInfo> _browseHistoryFolders = [];

  // 下载历史状态
  List<HistoryInfo> _downloadHistory = [];
  List<FolderInfo> _downloadHistoryFolders = [];

  // 视频浏览状态
  List<FolderInfo> _videoFolders = [];
  List<FileInfo> _videoFiles = [];
  List<FolderTreeNode> _videoTreeNodes = [];
  String? _selectedVideoTreePath;
  VideoViewMode _videoViewMode = VideoViewMode.favorites;

  // 视频收藏状态
  List<FavoriteInfo> _videoFavorites = [];
  List<FileInfo> _videoFavoriteFiles = [];

  // 视频浏览历史状态
  List<HistoryInfo> _videoBrowseHistory = [];
  List<FileInfo> _videoBrowseHistoryFiles = [];

  // 侧边栏状态
  bool _isSidebarExpanded = true;

  // Getters
  ServerInfo? get connectedServer => _connectedServer;
  ApiClient? get apiClient => _apiClient;
  ServerDiscovery get discovery => _discovery;
  List<FolderInfo> get folders => _folders;
  List<FileInfo> get files => _files;
  FolderInfo? get currentFolder => _currentFolder;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isConnected => _connectedServer != null && _apiClient != null;
  int get currentPage => _currentPage;
  bool get hasMore => _hasMore;
  int get totalFolders => _totalFolders;

  // 树 Getters
  List<FolderTreeNode> get treeNodes => _treeNodes;
  String? get selectedTreePath => _selectedTreePath;

  // 视图模式 Getter
  ViewMode get viewMode => _viewMode;

  // 收藏 Getters
  List<FavoriteInfo> get favorites => _favorites;
  List<FolderInfo> get favoriteFolders => _favoriteFolders;

  // 历史 Getters
  List<HistoryInfo> get browseHistory => _browseHistory;
  List<FolderInfo> get browseHistoryFolders => _browseHistoryFolders;
  List<HistoryInfo> get downloadHistory => _downloadHistory;
  List<FolderInfo> get downloadHistoryFolders => _downloadHistoryFolders;

  // 视频 Getters
  List<FolderInfo> get videoFolders => _videoFolders;
  List<FileInfo> get videoFiles => _videoFiles;
  List<FolderTreeNode> get videoTreeNodes => _videoTreeNodes;
  String? get selectedVideoTreePath => _selectedVideoTreePath;
  VideoViewMode get videoViewMode => _videoViewMode;
  List<FavoriteInfo> get videoFavorites => _videoFavorites;
  List<FileInfo> get videoFavoriteFiles => _videoFavoriteFiles;
  List<HistoryInfo> get videoBrowseHistory => _videoBrowseHistory;
  List<FileInfo> get videoBrowseHistoryFiles => _videoBrowseHistoryFiles;

  // 侧边栏 Getter
  bool get isSidebarExpanded => _isSidebarExpanded;

  /// 读取上次成功连接的服务器（无记录返回 null）
  static Future<ServerInfo?> getLastServer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ip = prefs.getString(_lastServerIpKey);
      final port = prefs.getInt(_lastServerPortKey);
      if (ip == null || ip.isEmpty || port == null) return null;
      return ServerInfo(name: 'Comic Reader', hostname: ip, ip: ip, port: port);
    } catch (_) {
      return null;
    }
  }

  /// 持久化上次成功连接的服务器
  static Future<void> _saveLastServer(ServerInfo server) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastServerIpKey, server.ip);
      await prefs.setInt(_lastServerPortKey, server.port);
    } catch (_) {
      // 持久化失败不影响连接流程
    }
  }

  /// 连接到服务器
  /// [timeout] 连接测试超时（重连上次服务器时可缩短）
  Future<bool> connectToServer(
    ServerInfo server, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final client = ApiClient(baseUrl: server.baseUrl);
      final connected = await client.testConnection(timeout: timeout);
      if (connected) {
        // 获取完整的服务器信息（包含 resourcePath、videoResourcePath 等）
        final fullServerInfo = await client.getServerInfo();
        _connectedServer = fullServerInfo ?? server;
        _apiClient = client;
        _isLoading = false;
        _saveLastServer(_connectedServer!);
        // 服务器可能更换，重置视频封面接口探测状态
        VideoThumbnailService.instance.resetServerCoverSupport();
        notifyListeners();
        return true;
      } else {
        _errorMessage = '无法连接到服务器';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = '连接服务器失败，请确认电脑端已启动并处于同一局域网';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// 断开连接
  void disconnect() {
    _connectedServer = null;
    _apiClient?.close();
    _apiClient = null;
    _folders = [];
    _files = [];
    _currentFolder = null;
    _currentPage = 0;
    _hasMore = true;
    _errorMessage = null;
    _treeNodes = [];
    _selectedTreePath = null;
    _favorites = [];
    _favoriteFolders = [];
    _browseHistory = [];
    _browseHistoryFolders = [];
    _downloadHistory = [];
    _downloadHistoryFolders = [];
    _videoFolders = [];
    _videoFiles = [];
    _videoTreeNodes = [];
    _selectedVideoTreePath = null;
    _videoFavorites = [];
    _videoFavoriteFiles = [];
    _videoBrowseHistory = [];
    _videoBrowseHistoryFiles = [];
    notifyListeners();
  }

  // ==================== 视图模式 ====================

  void setViewMode(ViewMode mode) {
    if (_viewMode == mode) return;
    _viewMode = mode;
    _folders = [];
    _favoriteFolders = [];
    _browseHistoryFolders = [];
    _downloadHistoryFolders = [];
    notifyListeners();
    _loadDataForMode(mode);
  }

  Future<void> _loadDataForMode(ViewMode mode) async {
    switch (mode) {
      case ViewMode.folders:
        if (_selectedTreePath != null) {
          await loadFolders(path: _selectedTreePath);
        } else {
          await loadFolders();
        }
        break;
      case ViewMode.favorites:
        await loadFavorites();
        break;
      case ViewMode.history:
        await loadBrowseHistory();
        break;
      case ViewMode.downloads:
        await loadDownloadHistory();
        break;
    }
  }

  // ==================== 文件夹树 ====================

  /// 加载文件夹树：每个数据源作为顶层根节点（可展开）
  void loadTreeRoot(List<String> rootPaths) {
    if (rootPaths.isEmpty) return;
    _treeNodes = rootPaths
        .where((p) => p.isNotEmpty)
        .map((p) => FolderTreeNode(name: _pathBasename(p), fullPath: p, isLeaf: false))
        .toList();
    _rebuildBookmarkGroup();
    notifyListeners();
  }

  /// 重建树顶"已收藏"虚拟分组（收藏目录汇总，与 Electron 端一致）
  void _rebuildBookmarkGroup() {
    _treeNodes.removeWhere((n) => n.fullPath == bookmarkGroupKey);
    if (_favorites.isEmpty) return;

    final group = FolderTreeNode(
      name: '已收藏',
      fullPath: bookmarkGroupKey,
      isLeaf: false,
      isExpanded: true,
      isBookmarkGroup: true,
      children: _favorites
          .where((f) => f.fullPath.isNotEmpty)
          .map(
            (f) => FolderTreeNode(
              name: _pathBasename(f.fullPath),
              fullPath: f.fullPath,
              isLeaf: false,
              isBookmarked: true,
            ),
          )
          .toList(),
    );
    _treeNodes.insert(0, group);
  }

  /// 轻量刷新收藏路径列表（仅拉收藏表，重建树分组；不拉每项详情）
  Future<void> _refreshFavoritePaths() async {
    if (_apiClient == null) return;
    try {
      _favorites = await _apiClient!.getFavorites(module: 'book');
      _rebuildBookmarkGroup();
    } catch (_) {
      // 刷新失败保持现状
    }
  }

  /// 提取路径最后一段作为名称（兼容 / 与 \）
  static String _pathBasename(String path) {
    final parts = path.split(RegExp(r'[/\\]'));
    return parts.isEmpty || parts.last.isEmpty ? path : parts.last;
  }

  /// 懒加载树的子节点
  Future<void> loadTreeChildren(FolderTreeNode node) async {
    if (_apiClient == null || node.isLoading || node.children.isNotEmpty) {
      return;
    }
    node.isLoading = true;
    notifyListeners();

    try {
      final children = await _apiClient!.getFolderTree(path: node.fullPath);
      node.children = children
          .map(
            (f) => FolderTreeNode(
              name: f.name,
              fullPath: f.fullPath,
              isLeaf: f.isLeaf,
              children: [],
              isExpanded: false,
              isLoading: false,
            ),
          )
          .toList();
      node.isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = '加载子节点失败: $e';
      node.isLoading = false;
      notifyListeners();
    }
  }

  /// 选中树节点并加载文件列表
  Future<void> selectTreeNode(String fullPath) async {
    _selectedTreePath = fullPath;
    _viewMode = ViewMode.folders;
    notifyListeners();
    await loadFolders(path: fullPath);
  }

  // ==================== 文件夹列表 ====================

  /// 加载文件夹列表
  Future<void> loadFolders({String? path}) async {
    if (_apiClient == null) return;
    _isLoading = true;
    _errorMessage = null;
    _currentPage = 0;
    _hasMore = true;
    notifyListeners();

    try {
      final result = await _apiClient!.getFolderList(
        path: path,
        page: 0,
        pageSize: 50,
      );
      final folderList = result['folders'] as List<dynamic>? ?? [];
      _folders = folderList
          .map((f) => FolderInfo.fromJson(f as Map<String, dynamic>))
          .toList();
      _totalFolders = result['total'] as int? ?? 0;
      _currentPage = 0;
      _hasMore = _folders.length < _totalFolders;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = '加载文件夹失败: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 加载更多文件夹（下一页）
  Future<void> loadMoreFolders({String? path}) async {
    if (_apiClient == null || !_hasMore || _isLoading) return;
    _isLoading = true;
    notifyListeners();

    try {
      final nextPage = _currentPage + 1;
      final result = await _apiClient!.getFolderList(
        path: path,
        page: nextPage,
        pageSize: 50,
      );
      final folderList = result['folders'] as List<dynamic>? ?? [];
      _folders.addAll(
        folderList
            .map((f) => FolderInfo.fromJson(f as Map<String, dynamic>))
            .toList(),
      );
      _currentPage = nextPage;
      _hasMore = _folders.length < _totalFolders;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = '加载更多失败: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 加载文件夹内的文件列表
  Future<void> loadFiles(String folderPath) async {
    if (_apiClient == null) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _files = await _apiClient!.getFiles(folderPath);
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = '加载文件列表失败: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 设置当前文件夹
  void setCurrentFolder(FolderInfo? folder) {
    _currentFolder = folder;
    notifyListeners();
  }

  // ==================== 收藏相关 ====================

  /// 加载收藏列表
  Future<void> loadFavorites() async {
    if (_apiClient == null) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _favorites = await _apiClient!.getFavorites(module: 'book');
      // 并发获取每个收藏的详细信息（限并发，避免串行等待）
      _favoriteFolders = await _mapLimited<FavoriteInfo, FolderInfo>(
        _favorites,
        (fav) async {
          try {
            return await _apiClient!.getFolderInfo(fav.fullPath);
          } catch (_) {
            return _fallbackFolderInfo(fav.fullPath, bookmarked: true);
          }
        },
      );
      _rebuildBookmarkGroup();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = '加载收藏失败: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 切换收藏状态
  Future<void> toggleFavorite(String fullPath) async {
    if (_apiClient == null) return;
    try {
      await _apiClient!.toggleFavorite(fullPath, 'book');
      // 刷新收藏列表（含树顶"已收藏"分组）
      if (_viewMode == ViewMode.favorites) {
        await loadFavorites();
      } else {
        await _refreshFavoritePaths();
        notifyListeners();
      }
    } catch (e) {
      _errorMessage = '切换收藏失败: $e';
      notifyListeners();
    }
  }

  /// 检查是否已收藏
  Future<bool> isFavorited(String fullPath) async {
    if (_apiClient == null) return false;
    try {
      return await _apiClient!.isFavorited(fullPath, 'book');
    } catch (_) {
      return false;
    }
  }

  // ==================== 浏览历史 ====================

  /// 加载浏览历史
  Future<void> loadBrowseHistory() async {
    if (_apiClient == null) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _browseHistory = await _apiClient!.getBrowseHistory(
        limit: 100,
        module: 'book',
      );
      _browseHistoryFolders = await _mapLimited<HistoryInfo, FolderInfo>(
        _browseHistory,
        (record) async {
          try {
            return await _apiClient!.getFolderInfo(record.fullPath);
          } catch (_) {
            return _fallbackFolderInfo(record.fullPath);
          }
        },
      );
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = '加载浏览历史失败: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 记录浏览历史
  Future<void> recordBrowseHistory(String fullPath) async {
    if (_apiClient == null) return;
    try {
      await _apiClient!.addBrowseHistory(fullPath, 'book');
    } catch (_) {
      // 静默处理记录失败
    }
  }

  /// 按路径删除一条浏览历史并同步列表
  Future<void> removeBrowseHistoryByPath(String fullPath) async {
    if (_apiClient == null) return;
    final record = _browseHistory
        .where((h) => h.fullPath == fullPath)
        .firstOrNull;
    if (record == null) return;
    try {
      if (record.id != null) {
        await _apiClient!.deleteBrowseHistory(record.id!);
      }
      _browseHistory.remove(record);
      _browseHistoryFolders.removeWhere((f) => f.fullPath == fullPath);
      notifyListeners();
    } catch (e) {
      _errorMessage = '删除历史记录失败: $e';
      notifyListeners();
    }
  }

  // ==================== 下载历史 ====================

  /// 加载下载历史
  Future<void> loadDownloadHistory() async {
    if (_apiClient == null) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _downloadHistory = await _apiClient!.getDownloadHistory(
        limit: 100,
        module: 'book',
      );
      _downloadHistoryFolders = await _mapLimited<HistoryInfo, FolderInfo>(
        _downloadHistory,
        (record) async {
          try {
            return await _apiClient!.getFolderInfo(record.fullPath);
          } catch (_) {
            return _fallbackFolderInfo(record.fullPath);
          }
        },
      );
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = '加载下载历史失败: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  // ==================== 侧边栏 ====================

  void toggleSidebar() {
    _isSidebarExpanded = !_isSidebarExpanded;
    notifyListeners();
  }

  void setSidebarExpanded(bool expanded) {
    _isSidebarExpanded = expanded;
    notifyListeners();
  }

  /// 清除错误信息
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  // ==================== 辅助方法 ====================

  /// 并发受限地映射列表（避免 N+1 串行请求拖慢加载）
  Future<List<R>> _mapLimited<T, R>(
    List<T> items,
    Future<R> Function(T) convert,
  ) async {
    const limit = 8;
    final results = <R>[];
    for (var i = 0; i < items.length; i += limit) {
      final chunk = items.skip(i).take(limit);
      results.addAll(await Future.wait(chunk.map(convert)));
    }
    return results;
  }

  /// 从路径提取名称构造基本 FolderInfo（详情请求失败时的兜底）
  FolderInfo _fallbackFolderInfo(String fullPath, {bool bookmarked = false}) {
    final pathParts = fullPath.split(RegExp(r'[/\\]'));
    final name = pathParts.isNotEmpty ? pathParts.last : fullPath;
    return FolderInfo(
      name: name,
      fullPath: fullPath,
      isBookmarked: bookmarked,
    );
  }

  // ==================== 视频浏览 ====================

  /// 加载视频文件夹树：每个视频数据源作为顶层根节点（可展开）
  void loadVideoTreeRoot(List<String> rootPaths) {
    if (rootPaths.isEmpty) return;
    _videoTreeNodes = rootPaths
        .where((p) => p.isNotEmpty)
        .map((p) => FolderTreeNode(name: _pathBasename(p), fullPath: p, isLeaf: false))
        .toList();
    notifyListeners();
  }

  /// 懒加载视频树子节点
  Future<void> loadVideoTreeChildren(FolderTreeNode node) async {
    if (_apiClient == null || node.isLoading || node.children.isNotEmpty) {
      return;
    }
    node.isLoading = true;
    notifyListeners();

    try {
      // 视频模块显示全部子目录（含叶子）
      final children = await _apiClient!.getFolderTree(
        path: node.fullPath,
        includeLeaf: true,
      );
      node.children = children
          .map(
            (f) => FolderTreeNode(
              name: f.name,
              fullPath: f.fullPath,
              isLeaf: f.isLeaf,
              children: [],
              isExpanded: false,
              isLoading: false,
            ),
          )
          .toList();
      node.isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = '加载子节点失败: $e';
      node.isLoading = false;
      notifyListeners();
    }
  }

  /// 选中视频树节点并加载视频文件
  Future<void> selectVideoTreeNode(String fullPath) async {
    _selectedVideoTreePath = fullPath;
    _videoViewMode = VideoViewMode.folders;
    notifyListeners();
    await loadVideoFiles(fullPath);
  }

  /// 加载指定文件夹中的视频文件
  Future<void> loadVideoFiles(String folderPath) async {
    if (_apiClient == null) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final allFiles = await _apiClient!.getFiles(folderPath);
      _videoFiles = allFiles.where((f) => f.isVideo).toList();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = '加载视频文件失败: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 设置视频视图模式
  void setVideoViewMode(VideoViewMode mode) {
    if (_videoViewMode == mode) return;
    _videoViewMode = mode;
    notifyListeners();
    _loadVideoDataForMode(mode);
  }

  Future<void> _loadVideoDataForMode(VideoViewMode mode) async {
    switch (mode) {
      case VideoViewMode.folders:
        if (_selectedVideoTreePath != null) {
          await loadVideoFiles(_selectedVideoTreePath!);
        }
        break;
      case VideoViewMode.favorites:
        await loadVideoFavorites();
        break;
      case VideoViewMode.history:
        await loadVideoBrowseHistory();
        break;
    }
  }

  // ==================== 视频收藏 ====================

  /// 加载视频收藏列表
  Future<void> loadVideoFavorites() async {
    if (_apiClient == null) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _videoFavorites = await _apiClient!.getFavorites(module: 'video');
      _videoFavoriteFiles = _videoFavorites.map((fav) {
        final pathParts = fav.fullPath.split(RegExp(r'[/\\]'));
        final name = pathParts.isNotEmpty ? pathParts.last : fav.fullPath;
        final ext = name.contains('.') ? '.${name.split('.').last}' : '';
        return FileInfo(
          name: name,
          fullPath: fav.fullPath,
          extension: ext,
          size: 0,
          modifiedTime: '',
        );
      }).toList();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = '加载视频收藏失败: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 切换视频收藏状态
  Future<void> toggleVideoFavorite(String fullPath) async {
    if (_apiClient == null) return;
    try {
      await _apiClient!.toggleFavorite(fullPath, 'video');
      if (_videoViewMode == VideoViewMode.favorites) {
        await loadVideoFavorites();
      }
      notifyListeners();
    } catch (e) {
      _errorMessage = '切换收藏失败: $e';
      notifyListeners();
    }
  }

  /// 检查视频是否已收藏
  Future<bool> isVideoFavorited(String fullPath) async {
    if (_apiClient == null) return false;
    try {
      return await _apiClient!.isFavorited(fullPath, 'video');
    } catch (_) {
      return false;
    }
  }

  // ==================== 视频浏览历史 ====================

  /// 加载视频浏览历史
  Future<void> loadVideoBrowseHistory() async {
    if (_apiClient == null) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _videoBrowseHistory = await _apiClient!.getBrowseHistory(
        limit: 100,
        module: 'video',
      );
      _videoBrowseHistoryFiles = _videoBrowseHistory.map((record) {
        final pathParts = record.fullPath.split(RegExp(r'[/\\]'));
        final name = pathParts.isNotEmpty ? pathParts.last : record.fullPath;
        final ext = name.contains('.') ? '.${name.split('.').last}' : '';
        return FileInfo(
          name: name,
          fullPath: record.fullPath,
          extension: ext,
          size: 0,
          modifiedTime: '',
        );
      }).toList();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = '加载视频浏览历史失败: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 记录视频浏览历史
  Future<void> recordVideoBrowseHistory(String fullPath) async {
    if (_apiClient == null) return;
    try {
      await _apiClient!.addBrowseHistory(fullPath, 'video');
    } catch (_) {
      // 静默处理记录失败
    }
  }

  @override
  void dispose() {
    _discovery.dispose();
    super.dispose();
  }
}

/// 文件夹树节点
class FolderTreeNode {
  final String name;
  final String fullPath;
  final bool isLeaf;

  /// 树顶"已收藏"虚拟分组节点
  final bool isBookmarkGroup;

  /// 已收藏的目录（分组内节点显示书签图标）
  final bool isBookmarked;
  List<FolderTreeNode> children;
  bool isExpanded;
  bool isLoading;

  FolderTreeNode({
    required this.name,
    required this.fullPath,
    this.isLeaf = true,
    this.isBookmarkGroup = false,
    this.isBookmarked = false,
    this.children = const [],
    this.isExpanded = false,
    this.isLoading = false,
  });
}
