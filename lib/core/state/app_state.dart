import 'package:flutter/material.dart';
import '../models/server_info.dart';
import '../models/folder_info.dart';
import '../models/file_info.dart';
import '../models/favorite_info.dart';
import '../models/history_info.dart';
import '../network/api_client.dart';
import '../network/server_discovery.dart';

/// 视图模式
enum ViewMode { folders, favorites, history, downloads }

/// 应用全局状态管理
class AppState extends ChangeNotifier {
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
  bool _isTreeLoading = false;

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
  bool get isTreeLoading => _isTreeLoading;

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

  // 侧边栏 Getter
  bool get isSidebarExpanded => _isSidebarExpanded;

  /// 连接到服务器
  Future<bool> connectToServer(ServerInfo server) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final client = ApiClient(baseUrl: server.baseUrl);
      final connected = await client.testConnection();
      if (connected) {
        _connectedServer = server;
        _apiClient = client;
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _errorMessage = '无法连接到服务器';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = '连接失败: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// 通过 IP 地址手动连接
  Future<bool> connectByIp(String ip, {int port = 9527}) async {
    final server = ServerInfo(
      name: 'Comic Reader',
      hostname: ip,
      ip: ip,
      port: port,
    );
    return connectToServer(server);
  }

  /// 断开连接
  void disconnect() {
    _connectedServer = null;
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

  /// 加载文件夹树的根节点
  Future<void> loadTreeRoot(String rootPath) async {
    if (_apiClient == null) return;
    _isTreeLoading = true;
    notifyListeners();

    try {
      final children = await _apiClient!.getFolderTree(path: rootPath);
      _treeNodes = children
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
      _isTreeLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = '加载文件夹树失败: $e';
      _isTreeLoading = false;
      notifyListeners();
    }
  }

  /// 懒加载树的子节点
  Future<void> loadTreeChildren(FolderTreeNode node) async {
    if (_apiClient == null || node.isLoading || node.children.isNotEmpty)
      return;
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
      // 将收藏转换为 FolderInfo 列表（获取每个收藏的详细信息）
      final folderInfoList = <FolderInfo>[];
      for (final fav in _favorites) {
        try {
          final info = await _apiClient!.getFolderInfo(fav.fullPath);
          folderInfoList.add(info);
        } catch (_) {
          // 获取详细信息失败，使用基本信息
          final pathParts = fav.fullPath.split(RegExp(r'[/\\]'));
          final name = pathParts.isNotEmpty ? pathParts.last : fav.fullPath;
          folderInfoList.add(
            FolderInfo(
              name: name ?? '',
              fullPath: fav.fullPath,
              isBookmarked: true,
            ),
          );
        }
      }
      _favoriteFolders = folderInfoList;
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
      final result = await _apiClient!.toggleFavorite(fullPath, 'book');
      // 刷新收藏列表
      if (_viewMode == ViewMode.favorites) {
        await loadFavorites();
      }
      notifyListeners();
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
      final folderInfoList = <FolderInfo>[];
      for (final record in _browseHistory) {
        try {
          final info = await _apiClient!.getFolderInfo(record.fullPath);
          folderInfoList.add(info);
        } catch (_) {
          final pathParts = record.fullPath.split(RegExp(r'[/\\]'));
          final name = pathParts.isNotEmpty ? pathParts.last : record.fullPath;
          folderInfoList.add(
            FolderInfo(name: name ?? '', fullPath: record.fullPath),
          );
        }
      }
      _browseHistoryFolders = folderInfoList;
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
      final folderInfoList = <FolderInfo>[];
      for (final record in _downloadHistory) {
        try {
          final info = await _apiClient!.getFolderInfo(record.fullPath);
          folderInfoList.add(info);
        } catch (_) {
          final pathParts = record.fullPath.split(RegExp(r'[/\\]'));
          final name = pathParts.isNotEmpty ? pathParts.last : record.fullPath;
          folderInfoList.add(
            FolderInfo(name: name ?? '', fullPath: record.fullPath),
          );
        }
      }
      _downloadHistoryFolders = folderInfoList;
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
  List<FolderTreeNode> children;
  bool isExpanded;
  bool isLoading;

  FolderTreeNode({
    required this.name,
    required this.fullPath,
    this.isLeaf = true,
    this.children = const [],
    this.isExpanded = false,
    this.isLoading = false,
  });
}
