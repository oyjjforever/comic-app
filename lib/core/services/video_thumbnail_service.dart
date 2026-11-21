import 'dart:typed_data';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:media_kit/media_kit.dart';
import 'package:image/image.dart' as img;

/// 视频缩略图服务
/// 获取顺序：
/// 1. 内存/磁盘缓存
/// 2. 服务器封面接口（/api/video-cover，ffmpeg 生成，全端共享）——新服务器
/// 3. 本地 media_kit (libmpv) 解码视频帧生成——旧服务器回退方案
/// 本地生成优化：
/// - 双 Player 并行处理（速度翻倍）
/// - 截图后压缩为 240px JPEG quality 50（~15KB）
/// - 8 秒超时，不重试
class VideoThumbnailService {
  VideoThumbnailService._();
  static final VideoThumbnailService instance = VideoThumbnailService._();

  // 缩略图参数
  static const int _thumbnailWidth = 240;
  static const int _jpegQuality = 50;
  static const int _poolSize = 2;
  static const Duration _frameTimeout = Duration(seconds: 8);
  static const Duration _serverCoverTimeout = Duration(seconds: 15);

  // 内存缓存：videoUrl -> thumbnail bytes
  final Map<String, Uint8List?> _memoryCache = {};

  // 正在生成的请求去重
  final Map<String, Future<Uint8List?>> _pendingRequests = {};

  // Player 池
  final List<_PooledPlayer> _pool = [];
  bool _initialized = false;

  // 待处理队列
  final List<_ThumbnailJob> _queue = [];

  // 服务器封面接口支持状态（null=未探测，true=支持，false=不支持/旧服务器）
  bool? _serverCoverSupported;

  // 磁盘缓存目录（惰性初始化）
  static const String _coverDirName = 'video-covers';
  Directory? _coverDir;
  bool _dirLoading = false;

  /// 重置服务器封面接口探测状态（重连服务器后调用）
  void resetServerCoverSupport() {
    _serverCoverSupported = null;
  }

  /// 获取磁盘缓存目录
  Future<Directory?> _getCoverDir() async {
    if (_coverDir != null) return _coverDir;
    if (_dirLoading) {
      // 等待其他调用完成初始化
      while (_dirLoading) {
        await Future.delayed(const Duration(milliseconds: 20));
      }
      return _coverDir;
    }
    _dirLoading = true;
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}${Platform.pathSeparator}$_coverDirName');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      _coverDir = dir;
    } catch (e) {
      debugPrint('[VideoThumbnail] 初始化封面缓存目录失败: $e');
    } finally {
      _dirLoading = false;
    }
    return _coverDir;
  }

  /// 根据视频 URL 生成稳定的封面文件名（md5，与 Electron 端方案一致）
  File _coverFile(String dirPath, String videoUrl) {
    final hash = md5.convert(utf8.encode(videoUrl)).toString();
    return File('$dirPath${Platform.pathSeparator}$hash.jpg');
  }

  /// 读取磁盘缓存的封面
  Future<Uint8List?> _readDiskCache(String videoUrl) async {
    try {
      final dir = await _getCoverDir();
      if (dir == null) return null;
      final file = _coverFile(dir.path, videoUrl);
      if (file.existsSync()) {
        return file.readAsBytes();
      }
    } catch (e) {
      debugPrint('[VideoThumbnail] 读取磁盘缓存失败: $e');
    }
    return null;
  }

  /// 写入磁盘缓存
  Future<void> _writeDiskCache(String videoUrl, Uint8List bytes) async {
    try {
      final dir = await _getCoverDir();
      if (dir == null) return;
      final file = _coverFile(dir.path, videoUrl);
      await file.writeAsBytes(bytes, flush: true);
    } catch (e) {
      debugPrint('[VideoThumbnail] 写入磁盘缓存失败: $e');
    }
  }

  /// 初始化 Player 池（带并发防护：多个触发点同时等待只初始化一次）
  Future<void>? _initFuture;
  Future<void> _ensureInitialized() {
    if (_initialized) return Future.value();
    return _initFuture ??= _initializePool().whenComplete(() {
      _initFuture = null;
      _initialized = true;
    });
  }

  Future<void> _initializePool() async {
    for (int i = 0; i < _poolSize; i++) {
      final completer = Completer<void>();
      final player = Player(
        configuration: PlayerConfiguration(
          ready: () {
            if (!completer.isCompleted) completer.complete();
          },
        ),
      );
      await completer.future;

      // 配置 Player：
      // vid=auto: 启用视频解码（默认 vid=no）
      // hwdec=no: 软件解码（缩略图无 Surface，不能用硬件解码）
      // ao=null: 禁用音频
      // vf=scale=240:-2: 缩小到 240px 宽（加速解码+减小截图）
      // demuxer-lavf-o=fflags=+ignidx: 忽略索引（moov 末尾的 MP4 无需先下载 moov）
      final nativePlayer = player.platform as dynamic;
      await nativePlayer.setProperty('vid', 'auto');
      await nativePlayer.setProperty('hwdec', 'no');
      await nativePlayer.setProperty('ao', 'null');
      await nativePlayer.setProperty('vf', 'scale=$_thumbnailWidth:-2');
      await nativePlayer.setProperty('demuxer-max-bytes', '100MiB');
      await nativePlayer.setProperty('demuxer-max-back-bytes', '50MiB');
      await nativePlayer.setProperty('demuxer-lavf-o', 'fflags=+ignidx');

      _pool.add(_PooledPlayer(player));
    }
  }

  /// 释放 Player 并触发队列处理
  void _releasePlayer(_PooledPlayer pp) {
    pp.inUse = false;
    _processQueue();
  }

  /// 请求服务器封面接口
  /// 返回 (封面字节, HTTP 状态码)；网络异常返回 null
  Future<(Uint8List?, int)?> _fetchServerCover(String coverUrl) async {
    try {
      final response = await http
          .get(Uri.parse(coverUrl))
          .timeout(_serverCoverTimeout);
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        return (response.bodyBytes, 200);
      }
      return (null, response.statusCode);
    } catch (_) {
      return null; // 网络异常/超时：不判定服务器是否支持
    }
  }

  /// 获取视频缩略图
  /// [videoUrl] 视频源 URL（同时作为缓存键）
  /// [serverCoverUrl] 服务器封面接口 URL（提供时优先尝试服务器 ffmpeg 封面）
  Future<Uint8List?> getThumbnail(
    String videoUrl, {
    String? serverCoverUrl,
  }) async {
    // 1. 检查内存缓存
    if (_memoryCache.containsKey(videoUrl)) {
      return _memoryCache[videoUrl];
    }

    // 2. 检查是否有正在进行的请求（去重）
    if (_pendingRequests.containsKey(videoUrl)) {
      return _pendingRequests[videoUrl]!;
    }

    // 3. 检查磁盘缓存（已生成的封面直接复用，避免重新解码视频）
    final cached = await _readDiskCache(videoUrl);
    if (cached != null) {
      _memoryCache[videoUrl] = cached;
      return cached;
    }

    // 4. 服务器封面优先（新服务器 ffmpeg 生成，移动端零解码）
    if (serverCoverUrl != null && _serverCoverSupported != false) {
      final result = await _fetchServerCover(serverCoverUrl);
      if (result != null) {
        final (bytes, status) = result;
        if (bytes != null) {
          _serverCoverSupported = true;
          _memoryCache[videoUrl] = bytes;
          _writeDiskCache(videoUrl, bytes);
          return bytes;
        }
        if (status == 404) {
          // 旧服务器无此接口，后续直接走本地生成
          _serverCoverSupported = false;
        }
        // 其他状态（500 等）：本文件生成失败，走本地回退
      }
    }

    // 5. 本地 mpv 生成（回退方案），创建任务并加入队列
    final completer = Completer<Uint8List?>();
    _queue.add(_ThumbnailJob(videoUrl, completer));
    final future = completer.future;
    _pendingRequests[videoUrl] = future;

    // 触发队列处理
    _processQueue();

    try {
      final result = await future;
      _memoryCache[videoUrl] = result;
      // 限制内存缓存大小
      if (_memoryCache.length > 100) {
        final keys = _memoryCache.keys.toList();
        for (int i = 0; i < 20; i++) {
          _memoryCache.remove(keys[i]);
        }
      }
      return result;
    } finally {
      _pendingRequests.remove(videoUrl);
    }
  }

  /// 处理队列：为每个空闲 Player 分配任务
  /// （首次调用时惰性初始化 Player 池）
  Future<void> _processQueue() async {
    if (_queue.isEmpty) return;
    await _ensureInitialized();

    while (_queue.isNotEmpty) {
      // 找一个空闲的 Player
      _PooledPlayer? availablePlayer;
      for (final pp in _pool) {
        if (!pp.inUse) {
          availablePlayer = pp;
          break;
        }
      }
      if (availablePlayer == null) break; // 所有 Player 都在忙

      final job = _queue.removeAt(0);
      availablePlayer.inUse = true;
      _processJob(job, availablePlayer);
    }
  }

  /// 执行单个缩略图生成任务
  Future<void> _processJob(_ThumbnailJob job, _PooledPlayer pp) async {
    try {
      final player = pp.player;
      final shortUrl = job.videoUrl.length > 80
          ? '${job.videoUrl.substring(0, 80)}...'
          : job.videoUrl;
      debugPrint('[VideoThumbnail] Loading: $shortUrl');

      // 打开视频并开始播放（ao=null 已禁用音频）
      await player.open(Media(job.videoUrl), play: true);

      // 等待视频帧就绪（最多 8 秒）
      bool ready = false;
      final startTime = DateTime.now();
      while (DateTime.now().difference(startTime) < _frameTimeout) {
        await Future.delayed(const Duration(milliseconds: 100));
        final w = player.state.width;
        final h = player.state.height;
        if (w != null && w > 0 && h != null && h > 0) {
          debugPrint(
              '[VideoThumbnail] Frame ready: ${w}x$h after ${DateTime.now().difference(startTime).inMilliseconds}ms');
          ready = true;
          break;
        }
      }

      Uint8List? screenshot;
      if (ready) {
        // 暂停并等待帧完全解码
        await player.pause();
        await Future.delayed(const Duration(milliseconds: 200));
        screenshot = await player.screenshot();

        if (screenshot != null) {
          screenshot = _compressThumbnail(screenshot);
          debugPrint(
              '[VideoThumbnail] Compressed: ${screenshot.length} bytes');
          // 持久化到磁盘缓存（异步，不阻塞后续播放）
          _writeDiskCache(job.videoUrl, screenshot);
        }
      } else {
        debugPrint(
            '[VideoThumbnail] Timeout: ${DateTime.now().difference(startTime).inMilliseconds}ms');
      }

      // 停止播放释放资源
      await player.stop();

      _releasePlayer(pp);
      job.completer.complete(screenshot);
    } catch (e) {
      debugPrint('[VideoThumbnail] Error: $e');
      try {
        await pp.player.stop();
      } catch (_) {}
      _releasePlayer(pp);

      // 如果 Player 已损坏，重置它
      if (e.toString().contains('disposed')) {
        await _resetPlayer(pp);
      }
      job.completer.complete(null);
    }
  }

  /// 压缩缩略图：确保不超过 _thumbnailWidth，JPEG quality 50
  Uint8List _compressThumbnail(Uint8List rawBytes) {
    final image = img.decodeImage(rawBytes);
    if (image == null) return rawBytes;

    // 如果图片宽度大于目标宽度，缩放
    if (image.width > _thumbnailWidth) {
      final targetHeight =
          (image.height * _thumbnailWidth / image.width).round();
      final resized =
          img.copyResize(image, width: _thumbnailWidth, height: targetHeight);
      return Uint8List.fromList(
          img.encodeJpg(resized, quality: _jpegQuality));
    }

    // 已经是目标大小，只调整质量
    return Uint8List.fromList(img.encodeJpg(image, quality: _jpegQuality));
  }

  /// 重置损坏的 Player
  Future<void> _resetPlayer(_PooledPlayer pp) async {
    try {
      pp.player.dispose();
    } catch (_) {}

    final completer = Completer<void>();
    pp.player = Player(
      configuration: PlayerConfiguration(
        ready: () {
          if (!completer.isCompleted) completer.complete();
        },
      ),
    );
    await completer.future;

    final nativePlayer = pp.player.platform as dynamic;
    await nativePlayer.setProperty('vid', 'auto');
    await nativePlayer.setProperty('hwdec', 'no');
    await nativePlayer.setProperty('ao', 'null');
    await nativePlayer.setProperty('vf', 'scale=$_thumbnailWidth:-2');
    await nativePlayer.setProperty('demuxer-max-bytes', '100MiB');
    await nativePlayer.setProperty('demuxer-max-back-bytes', '50MiB');
    await nativePlayer.setProperty('demuxer-lavf-o', 'fflags=+ignidx');
    pp.inUse = false;
  }

  /// 清除内存缓存
  void clearMemoryCache() {
    _memoryCache.clear();
  }

  /// 清除磁盘缓存
  Future<void> clearDiskCache() async {
    final dir = await _getCoverDir();
    if (dir == null || !dir.existsSync()) return;
    try {
      await dir.delete(recursive: true);
      _coverDir = null;
    } catch (e) {
      debugPrint('[VideoThumbnail] 清除磁盘缓存失败: $e');
    }
  }

  /// 释放资源
  void dispose() {
    for (final pp in _pool) {
      try {
        pp.player.dispose();
      } catch (_) {}
    }
    _pool.clear();
    _initialized = false;
  }
}

/// Player 池中的包装
class _PooledPlayer {
  Player player;
  bool inUse;
  _PooledPlayer(this.player) : inUse = false;
}

/// 缩略图生成任务
class _ThumbnailJob {
  final String videoUrl;
  final Completer<Uint8List?> completer;
  _ThumbnailJob(this.videoUrl, this.completer);
}
