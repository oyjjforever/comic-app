import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

/// APK 下载状态
enum DownloadStatus { idle, downloading, completed, failed, installing }

/// 下载服务
class DownloadService {
  final Dio _dio;

  DownloadService({Dio? dio}) : _dio = dio ?? Dio();

  CancelToken? _cancelToken;

  /// 下载 APK 并安装
  /// [downloadUrl] APK 下载链接
  /// [onProgress] 下载进度回调 (0-100)
  /// [onStatusChanged] 状态变化回调
  Future<void> downloadAndInstall({
    required String downloadUrl,
    required void Function(int progress) onProgress,
    required void Function(DownloadStatus status) onStatusChanged,
  }) async {
    try {
      onStatusChanged(DownloadStatus.downloading);
      _cancelToken = CancelToken();

      // 获取保存路径
      final savePath = await _getApkSavePath();
      final fileName = _extractFileName(downloadUrl);
      final fullPath = '$savePath/$fileName';

      // 删除已存在的旧 APK
      final existingFile = File(fullPath);
      if (await existingFile.exists()) {
        await existingFile.delete();
      }

      // 下载 APK
      await _dio.download(
        downloadUrl,
        fullPath,
        cancelToken: _cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final progress = (received / total * 100).toInt();
            onProgress(progress);
          }
        },
      );

      onStatusChanged(DownloadStatus.completed);

      // 安装 APK
      onStatusChanged(DownloadStatus.installing);
      final result = await OpenFilex.open(fullPath);

      if (result.type != ResultType.done) {
        throw Exception('无法打开安装器: ${result.message}');
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        onStatusChanged(DownloadStatus.idle);
        return;
      }
      onStatusChanged(DownloadStatus.failed);
      rethrow;
    } catch (e) {
      onStatusChanged(DownloadStatus.failed);
      rethrow;
    }
  }

  /// 取消下载
  void cancelDownload() {
    _cancelToken?.cancel('用户取消下载');
    _cancelToken = null;
  }

  /// 获取 APK 保存目录
  Future<String> _getApkSavePath() async {
    final directory = await getExternalStorageDirectory();
    if (directory != null) {
      // 使用外部存储的应用专属目录
      final apkDir = Directory('${directory.path}/apk');
      if (!await apkDir.exists()) {
        await apkDir.create(recursive: true);
      }
      return apkDir.path;
    }

    // 回退到缓存目录
    final cacheDir = await getTemporaryDirectory();
    return cacheDir.path;
  }

  /// 从 URL 中提取文件名
  String _extractFileName(String url) {
    final uri = Uri.parse(url);
    final pathSegments = uri.pathSegments;
    if (pathSegments.isNotEmpty) {
      final lastSegment = pathSegments.last;
      if (lastSegment.endsWith('.apk')) return lastSegment;
    }
    return 'update.apk';
  }

  /// 清理已下载的 APK 文件
  Future<void> cleanUpApkFiles() async {
    try {
      final savePath = await _getApkSavePath();
      final dir = Directory(savePath);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File && entity.path.endsWith('.apk')) {
            await entity.delete();
          }
        }
      }
    } catch (_) {
      // 静默处理清理失败
    }
  }
}
