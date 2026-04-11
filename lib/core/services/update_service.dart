import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// GitHub Release 信息
class GitHubRelease {
  final String tagName;
  final String name;
  final String body;
  final String htmlUrl;
  final List<GitHubAsset> assets;
  final DateTime publishedAt;

  GitHubRelease({
    required this.tagName,
    required this.name,
    required this.body,
    required this.htmlUrl,
    required this.assets,
    required this.publishedAt,
  });

  factory GitHubRelease.fromJson(Map<String, dynamic> json) {
    final assetsList = (json['assets'] as List<dynamic>? ?? [])
        .map((a) => GitHubAsset.fromJson(a as Map<String, dynamic>))
        .toList();

    return GitHubRelease(
      tagName: json['tag_name'] as String? ?? '',
      name: json['name'] as String? ?? '',
      body: json['body'] as String? ?? '',
      htmlUrl: json['html_url'] as String? ?? '',
      assets: assetsList,
      publishedAt: DateTime.parse(
        json['published_at'] as String? ?? DateTime.now().toIso8601String(),
      ),
    );
  }

  /// 获取 APK 下载链接（优先找 comic-app 开头的 APK，否则找任意 .apk 文件）
  String? get apkDownloadUrl {
    // 优先查找 comic-app 开头的 APK
    final releaseApk = assets.where(
      (a) => a.name.startsWith('comic-app') && a.name.endsWith('.apk'),
    );
    if (releaseApk.isNotEmpty) return releaseApk.first.browserDownloadUrl;

    // 否则查找任意 .apk 文件
    final anyApk = assets.where((a) => a.name.endsWith('.apk'));
    if (anyApk.isNotEmpty) return anyApk.first.browserDownloadUrl;

    return null;
  }

  /// 获取纯版本号（去掉 v 前缀）
  String get version => tagName.replaceFirst(RegExp(r'^v'), '');
}

/// GitHub Release Asset
class GitHubAsset {
  final String name;
  final String browserDownloadUrl;
  final int size;

  GitHubAsset({
    required this.name,
    required this.browserDownloadUrl,
    required this.size,
  });

  factory GitHubAsset.fromJson(Map<String, dynamic> json) {
    return GitHubAsset(
      name: json['name'] as String? ?? '',
      browserDownloadUrl: json['browser_download_url'] as String? ?? '',
      size: json['size'] as int? ?? 0,
    );
  }
}

/// 更新检测结果
class UpdateResult {
  final bool hasUpdate;
  final GitHubRelease? release;
  final String? errorMessage;

  UpdateResult({required this.hasUpdate, this.release, this.errorMessage});
}

/// 更新检测服务
class UpdateService {
  static const String githubOwner = 'oyjjforever';
  static const String githubRepo = 'comic-app';

  static const String _baseUrl = 'https://api.github.com';
  static const String _skippedVersionKey = 'skipped_version';
  static const String _lastCheckTimeKey = 'last_update_check_time';

  final http.Client _httpClient;

  UpdateService({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  /// 检查更新
  /// [forceCheck] 为 true 时忽略频率限制和跳过版本检查
  Future<UpdateResult> checkForUpdate({bool forceCheck = false}) async {
    try {
      // 获取最新 Release
      final release = await _fetchLatestRelease();
      if (release == null) {
        return UpdateResult(hasUpdate: false, errorMessage: '无法获取版本信息');
      }

      // 获取当前版本
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      // 比较版本
      final hasUpdate = _compareVersions(release.version, currentVersion) > 0;

      if (!hasUpdate) {
        // 记录检查时间
        await _saveLastCheckTime();
        return UpdateResult(hasUpdate: false);
      }

      // 非强制检查时，判断是否已跳过该版本
      if (!forceCheck) {
        // 检查频率限制（每天最多自动检测一次）
        if (!await _shouldCheckAutomatically()) {
          return UpdateResult(hasUpdate: false);
        }

        // 检查是否已跳过该版本
        final skippedVersion = await _getSkippedVersion();
        if (skippedVersion == release.version) {
          return UpdateResult(hasUpdate: false);
        }
      }

      // 记录检查时间
      await _saveLastCheckTime();

      return UpdateResult(hasUpdate: true, release: release);
    } catch (e) {
      return UpdateResult(hasUpdate: false, errorMessage: '检查更新失败: $e');
    }
  }

  /// 跳过指定版本
  Future<void> skipVersion(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_skippedVersionKey, version);
  }

  /// 获取已跳过的版本号
  Future<String?> _getSkippedVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_skippedVersionKey);
  }

  /// 判断是否应该自动检测（每天最多一次）
  Future<bool> _shouldCheckAutomatically() async {
    final prefs = await SharedPreferences.getInstance();
    final lastCheck = prefs.getString(_lastCheckTimeKey);
    if (lastCheck == null) return true;

    try {
      final lastCheckTime = DateTime.parse(lastCheck);
      final now = DateTime.now();
      return now.difference(lastCheckTime).inHours >= 24;
    } catch (_) {
      return true;
    }
  }

  /// 保存最后检查时间
  Future<void> _saveLastCheckTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastCheckTimeKey, DateTime.now().toIso8601String());
  }

  /// 从 GitHub API 获取最新 Release
  Future<GitHubRelease?> _fetchLatestRelease() async {
    final url = Uri.parse(
      '$_baseUrl/repos/$githubOwner/$githubRepo/releases/latest',
    );
    final response = await _httpClient.get(
      url,
      headers: {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return GitHubRelease.fromJson(json);
    } else if (response.statusCode == 404) {
      // 没有 Release
      return null;
    } else {
      throw Exception(
        'GitHub API 返回错误: ${response.statusCode} ${response.reasonPhrase}',
      );
    }
  }

  /// 比较版本号
  /// 返回正数表示 v1 > v2，负数表示 v1 < v2，0 表示相等
  int _compareVersions(String v1, String v2) {
    // 去掉可能的 v 前缀
    v1 = v1.replaceFirst(RegExp(r'^v'), '');
    v2 = v2.replaceFirst(RegExp(r'^v'), '');

    final parts1 = v1.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final parts2 = v2.split('.').map((p) => int.tryParse(p) ?? 0).toList();

    // 补齐长度
    while (parts1.length < 3) {
      parts1.add(0);
    }
    while (parts2.length < 3) {
      parts2.add(0);
    }

    for (var i = 0; i < 3; i++) {
      if (parts1[i] != parts2[i]) {
        return parts1[i].compareTo(parts2[i]);
      }
    }
    return 0;
  }
}
