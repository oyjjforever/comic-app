import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/folder_info.dart';
import '../models/file_info.dart';
import '../models/server_info.dart';
import '../models/favorite_info.dart';
import '../models/history_info.dart';

/// HTTP API 客户端 - 与 Electron 端 HTTP 服务通信
class ApiClient {
  final String baseUrl;
  final http.Client _httpClient;

  ApiClient({required this.baseUrl}) : _httpClient = http.Client();

  /// 释放 HTTP 连接（断开连接时调用，避免 keep-alive 连接累积）
  void close() {
    _httpClient.close();
  }

  /// 测试连接
  Future<bool> testConnection({Duration timeout = const Duration(seconds: 5)}) async {
    try {
      final response = await _httpClient
          .get(Uri.parse('$baseUrl/api/server/info'))
          .timeout(timeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 获取服务器信息
  Future<ServerInfo?> getServerInfo() async {
    try {
      final uri = Uri.parse('$baseUrl/api/server/info');
      final response = await _httpClient.get(uri);
      if (response.statusCode == 200) {
        final data = _parseJson(response.body);
        final parsedUri = Uri.parse(baseUrl);
        return ServerInfo(
          name: data['name'] as String? ?? '',
          hostname: data['hostname'] as String? ?? '',
          ip: parsedUri.host,
          port: parsedUri.port > 0 ? parsedUri.port : 9527,
          version: data['version'] as String? ?? '1.0.0',
          resourcePath: data['resourcePath'] as String? ?? '',
          videoResourcePath: data['videoResourcePath'] as String? ?? '',
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ==================== 文件浏览相关 ====================

  /// 获取文件夹树（默认非叶子节点；视频模块传 [includeLeaf] 显示全部）
  Future<List<FolderInfo>> getFolderTree({
    String? path,
    bool includeLeaf = false,
  }) async {
    final queryParams = <String, String>{};
    if (path != null) {
      queryParams['path'] = path;
    }
    if (includeLeaf) {
      queryParams['includeLeaf'] = 'true';
    }
    final queryString = queryParams.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final uri = Uri.parse(
      '$baseUrl/api/browse/tree${queryString.isNotEmpty ? '?$queryString' : ''}',
    );

    final response = await _httpClient.get(uri);
    _checkResponse(response);
    final data = _parseJson(response.body);
    final folders = data['folders'] as List<dynamic>? ?? [];
    return folders
        .map((f) => FolderInfo.fromJson(f as Map<String, dynamic>))
        .toList();
  }

  /// 获取叶子文件夹列表（分页）
  Future<Map<String, dynamic>> getFolderList({
    String? path,
    int page = 0,
    int pageSize = 50,
  }) async {
    final queryParams = <String, String>{
      'page': page.toString(),
      'pageSize': pageSize.toString(),
    };
    if (path != null) {
      queryParams['path'] = path;
    }
    final queryString = queryParams.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final uri = Uri.parse('$baseUrl/api/browse/list?$queryString');

    final response = await _httpClient.get(uri);
    _checkResponse(response);
    return _parseJson(response.body);
  }

  /// 获取文件夹内的文件列表
  Future<List<FileInfo>> getFiles(String path) async {
    final uri = Uri.parse(
      '$baseUrl/api/browse/files?path=${Uri.encodeComponent(path)}',
    );
    final response = await _httpClient.get(uri);
    _checkResponse(response);
    final data = _parseJson(response.body);
    final files = data['files'] as List<dynamic>? ?? [];
    return files
        .map((f) => FileInfo.fromJson(f as Map<String, dynamic>))
        .toList();
  }

  /// 获取文件夹详情
  Future<FolderInfo> getFolderInfo(String path) async {
    final uri = Uri.parse(
      '$baseUrl/api/browse/info?path=${Uri.encodeComponent(path)}',
    );
    final response = await _httpClient.get(uri);
    _checkResponse(response);
    final data = _parseJson(response.body);
    return FolderInfo.fromJson(data);
  }

  /// 构建文件 URL（用于图片加载）
  String buildFileUrl(String filePath) {
    return '$baseUrl/api/file?path=${Uri.encodeComponent(filePath)}';
  }

  /// 构建缩略图 URL
  String buildThumbnailUrl(String filePath) {
    return '$baseUrl/api/thumbnail?path=${Uri.encodeComponent(filePath)}';
  }

  // ==================== 收藏相关 ====================

  /// 获取收藏列表
  Future<List<FavoriteInfo>> getFavorites({
    String? module,
    String order = 'id DESC',
  }) async {
    final queryParams = <String, String>{'order': order};
    if (module != null) {
      queryParams['module'] = module;
    }
    final queryString = queryParams.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final uri = Uri.parse('$baseUrl/api/favorites?$queryString');

    final response = await _httpClient.get(uri);
    _checkResponse(response);
    final data = _parseJson(response.body);
    final favorites = data['favorites'] as List<dynamic>? ?? [];
    return favorites
        .map((f) => FavoriteInfo.fromJson(f as Map<String, dynamic>))
        .toList();
  }

  /// 检查是否已收藏
  Future<bool> isFavorited(String fullPath, String module) async {
    final uri = Uri.parse(
      '$baseUrl/api/favorites/check?fullPath=${Uri.encodeComponent(fullPath)}&module=${Uri.encodeComponent(module)}',
    );
    final response = await _httpClient.get(uri);
    _checkResponse(response);
    final data = _parseJson(response.body);
    return data['isFavorited'] as bool? ?? false;
  }

  /// 添加收藏
  Future<int> addFavorite(
    String fullPath,
    String module, {
    String? tags,
  }) async {
    final uri = Uri.parse('$baseUrl/api/favorites');
    final response = await _httpClient.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'fullPath': fullPath,
        'module': module,
        'tags': ?tags,
      }),
    );
    _checkResponse(response);
    final data = _parseJson(response.body);
    return data['id'] as int? ?? 0;
  }

  /// 删除收藏 by ID
  Future<void> deleteFavorite(int id) async {
    final uri = Uri.parse('$baseUrl/api/favorites/$id');
    final response = await _httpClient.delete(uri);
    _checkResponse(response);
  }

  /// 删除收藏 by path
  Future<void> deleteFavoriteByPath(String fullPath, String module) async {
    final uri = Uri.parse(
      '$baseUrl/api/favorites/by-path?fullPath=${Uri.encodeComponent(fullPath)}&module=${Uri.encodeComponent(module)}',
    );
    final response = await _httpClient.delete(uri);
    _checkResponse(response);
  }

  /// 切换收藏状态
  Future<bool> toggleFavorite(String fullPath, String module) async {
    final uri = Uri.parse('$baseUrl/api/favorites/toggle');
    final response = await _httpClient.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'fullPath': fullPath, 'module': module}),
    );
    _checkResponse(response);
    final data = _parseJson(response.body);
    return data['isFavorited'] as bool? ?? false;
  }

  /// 清空收藏
  Future<void> clearFavorites({String? module}) async {
    final queryParams = <String, String>{};
    if (module != null) {
      queryParams['module'] = module;
    }
    final queryString = queryParams.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final uri = Uri.parse(
      '$baseUrl/api/favorites/clear${queryString.isNotEmpty ? '?$queryString' : ''}',
    );
    final response = await _httpClient.delete(uri);
    _checkResponse(response);
  }

  // ==================== 浏览历史相关 ====================

  /// 获取浏览历史
  Future<List<HistoryInfo>> getBrowseHistory({
    int limit = 100,
    String? module,
  }) async {
    final queryParams = <String, String>{'limit': limit.toString()};
    if (module != null) {
      queryParams['module'] = module;
    }
    final queryString = queryParams.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final uri = Uri.parse('$baseUrl/api/history/browse?$queryString');

    final response = await _httpClient.get(uri);
    _checkResponse(response);
    final data = _parseJson(response.body);
    final history = data['history'] as List<dynamic>? ?? [];
    return history
        .map((h) => HistoryInfo.fromJson(h as Map<String, dynamic>))
        .toList();
  }

  /// 添加浏览历史
  Future<bool> addBrowseHistory(String fullPath, String module) async {
    final uri = Uri.parse('$baseUrl/api/history/browse');
    final response = await _httpClient.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'fullPath': fullPath, 'module': module}),
    );
    _checkResponse(response);
    final data = _parseJson(response.body);
    return data['success'] as bool? ?? false;
  }

  /// 删除浏览历史
  Future<void> deleteBrowseHistory(int id) async {
    final uri = Uri.parse('$baseUrl/api/history/browse/$id');
    final response = await _httpClient.delete(uri);
    _checkResponse(response);
  }

  /// 清空浏览历史
  Future<void> clearBrowseHistory({String? module}) async {
    final queryParams = <String, String>{};
    if (module != null) {
      queryParams['module'] = module;
    }
    final queryString = queryParams.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final uri = Uri.parse(
      '$baseUrl/api/history/browse/clear${queryString.isNotEmpty ? '?$queryString' : ''}',
    );
    final response = await _httpClient.delete(uri);
    _checkResponse(response);
  }

  // ==================== 下载历史相关 ====================

  /// 获取下载历史
  Future<List<HistoryInfo>> getDownloadHistory({
    int limit = 100,
    String? module,
  }) async {
    final queryParams = <String, String>{'limit': limit.toString()};
    if (module != null) {
      queryParams['module'] = module;
    }
    final queryString = queryParams.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final uri = Uri.parse('$baseUrl/api/history/download?$queryString');

    final response = await _httpClient.get(uri);
    _checkResponse(response);
    final data = _parseJson(response.body);
    final history = data['history'] as List<dynamic>? ?? [];
    return history
        .map((h) => HistoryInfo.fromJson(h as Map<String, dynamic>))
        .toList();
  }

  /// 添加下载历史
  Future<bool> addDownloadHistory(String fullPath, String module) async {
    final uri = Uri.parse('$baseUrl/api/history/download');
    final response = await _httpClient.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'fullPath': fullPath, 'module': module}),
    );
    _checkResponse(response);
    final data = _parseJson(response.body);
    return data['success'] as bool? ?? false;
  }

  /// 删除下载历史
  Future<void> deleteDownloadHistory(int id) async {
    final uri = Uri.parse('$baseUrl/api/history/download/$id');
    final response = await _httpClient.delete(uri);
    _checkResponse(response);
  }

  /// 清空下载历史
  Future<void> clearDownloadHistory({String? module}) async {
    final queryParams = <String, String>{};
    if (module != null) {
      queryParams['module'] = module;
    }
    final queryString = queryParams.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final uri = Uri.parse(
      '$baseUrl/api/history/download/clear${queryString.isNotEmpty ? '?$queryString' : ''}',
    );
    final response = await _httpClient.delete(uri);
    _checkResponse(response);
  }

  // ==================== 辅助方法 ====================

  void _checkResponse(http.Response response) {
    if (response.statusCode != 200) {
      final body = _parseJson(response.body);
      throw Exception(body['error'] as String? ?? 'Unknown error');
    }
  }

  Map<String, dynamic> _parseJson(String body) {
    return json.decode(body) as Map<String, dynamic>;
  }
}
