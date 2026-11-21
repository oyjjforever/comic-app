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

/// 视频缩略图结果：封面字节 + 元数据（分辨率/时长）
class VideoThumbnail {
  final Uint8List? bytes;
  final int? width;
  final int? height;
  final double? durationSeconds;

  const VideoThumbnail({this.bytes, this.width, this.height, this.durationSeconds});

  bool get hasMeta => width != null && height != null;

  /// 分辨率标签：4K / 1080p / 720p ...
  String get resolutionLabel {
    final h = height ?? 0;
    if (h >= 2000) return '4K';
    if (h >= 1000) return '1080p';
    if (h >= 700) return '720p';
    if (h >= 400) return '480p';
    return h > 0 ? '${h}p' : '';
  }

  /// 时长标签：mm:ss / h:mm:ss
  String get formattedDuration {
    final d = durationSeconds;
    if (d == null || d <= 0) return '';
    final total = d.round();
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final seconds = total % 60;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
  }

  /// 副标题："1080p · 42:10"（缺项自动省略）
  String get subtitleLabel {
    final parts = [
      if (resolutionLabel.isNotEmpty) resolutionLabel,
      if (formattedDuration.isNotEmpty) formattedDuration,
    ];
    return parts.join(' · ');
  }

  Map<String, dynamic> toMetaJson() => {
        if (width != null) 'w': width,
        if (height != null) 'h': height,
        if (durationSeconds != null) 'd': durationSeconds,
      };

  static VideoThumbnail? fromMetaJson(Map<String, dynamic> json) {
    final w = json['w'] as int?;
    final h = json['h'] as int?;
    final d = (json['d'] as num?)?.toDouble();
    if (w == null && h == null && d == null) return null;
    return VideoThumbnail(width: w, height: h, durationSeconds: d);
  }
}

/// 视频缩略图服务
/// 获取顺序：
/// 1. 内存/磁盘缓存
/// 2. 服务器封面接口（/api/video-cover，ffmpeg 生成，全端共享，响应头带元数据）——新服务器
/// 3. 本地 media_kit (libmpv) 解码视频帧生成（顺带捕获宽高/时长）——旧服务器回退
class VideoThumbnailService {
  VideoThumbnailService._();
  static final VideoThumbnailService instance = VideoThumbnailService._();

  // 缩略图参数
  static const int _thumbnailWidth = 240;
  static const int _jpegQuality = 50;
  static const int _poolSize = 2;
  static const Duration _frameTimeout = Duration(seconds: 8);
  static const Duration _serverCoverTimeout = Duration(seconds: 15);

  // 内存缓存：videoUrl -> 缩略图（含元数据）
  final Map<String, VideoThumbnail> _memoryCache = {};

  // 正在生成的请求去重
  final Map<String, Future<VideoThumbnail?>> _pendingRequests = {};

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

  /// 根据视频 URL 生成稳定的缓存文件基名（md5，与 Electron 端方案一致）
  String _cacheKey(String videoUrl) =>
      md5.convert(utf8.encode(videoUrl)).toString();

  File _coverFile(String dirPath, String videoUrl) =>
      File('$dirPath${Platform.pathSeparator}${_cacheKey(videoUrl)}.jpg');

  File _metaFile(String dirPath, String videoUrl) =>
      File('$dirPath${Platform.pathSeparator}${_cacheKey(videoUrl)}.json');

  /// 读取磁盘缓存（封面 jpg + 元数据 json sidecar）
  Future<VideoThumbnail?> _readDiskCache(String videoUrl) async {
    try {
      final dir = await _getCoverDir();
      if (dir == null) return null;

      Uint8List? bytes;
      final coverFile = _coverFile(dir.path, videoUrl);
      if (coverFile.existsSync()) {
        bytes = await coverFile.readAsBytes();
      }

      VideoThumbnail? metaOnly;
      final metaFile = _metaFile(dir.path, videoUrl);
      if (metaFile.existsSync()) {
        try {
          final json =
              jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
          metaOnly = VideoThumbnail.fromMetaJson(json);
        } catch (_) {
          // 元数据损坏，忽略
        }
      }

      if (bytes == null && metaOnly == null) return null;
      return VideoThumbnail(
        bytes: bytes,
        width: metaOnly?.width,
        height: metaOnly?.height,
        durationSeconds: metaOnly?.durationSeconds,
      );
    } catch (e) {
      debugPrint('[VideoThumbnail] 读取磁盘缓存失败: $e');
      return null;
    }
  }

  /// 写入磁盘缓存（封面与元数据 sidecar）
  Future<void> _writeDiskCache(String videoUrl, VideoThumbnail thumb) async {
    try {
      final dir = await _getCoverDir();
      if (dir == null) return;
      if (thumb.bytes != null) {
        await _coverFile(dir.path, videoUrl)
            .writeAsBytes(thumb.bytes!, flush: true);
      }
      if (thumb.hasMeta || thumb.durationSeconds != null) {
        await _metaFile(dir.path, videoUrl)
            .writeAsString(jsonEncode(thumb.toMetaJson()), flush: true);
      }
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
  /// 响应头带 X-Video-Width/Height/Duration（ffprobe 元数据）
  /// 返回 (结果, HTTP 状态码)；网络异常返回 null
  Future<(VideoThumbnail?, int)?> _fetchServerCover(String coverUrl) async {
    try {
      final response = await http
          .get(Uri.parse(coverUrl))
          .timeout(_serverCoverTimeout);
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        int? parseInt(String name) =>
            int.tryParse(response.headers[name] ?? '');
        final duration =
            double.tryParse(response.headers['x-video-duration'] ?? '');
        final thumb = VideoThumbnail(
          bytes: response.bodyBytes,
          width: parseInt('x-video-width'),
          height: parseInt('x-video-height'),
          durationSeconds: duration != null && duration > 0 ? duration : null,
        );
        return (thumb, 200);
      }
      return (null, response.statusCode);
    } catch (_) {
      return null; // 网络异常/超时：不判定服务器是否支持
    }
  }

  /// 获取视频缩略图（含元数据）
  /// [videoUrl] 视频源 URL（同时作为缓存键）
  /// [serverCoverUrl] 服务器封面接口 URL（提供时优先尝试服务器 ffmpeg 封面）
  Future<VideoThumbnail?> getThumbnail(
    String videoUrl, {
    String? serverCoverUrl,
  }) async {
    // 1. 检查内存缓存
    final cachedMem = _memoryCache[videoUrl];
    if (cachedMem != null) {
      return cachedMem;
    }

    // 2. 检查是否有正在进行的请求（去重）
    if (_pendingRequests.containsKey(videoUrl)) {
      return _pendingRequests[videoUrl]!;
    }

    // 3. 检查磁盘缓存（已生成的封面直接复用，避免重新解码视频）
    final cachedDisk = await _readDiskCache(videoUrl);
    if (cachedDisk != null) {
      // 旧版本缓存只有封面没有元数据：从服务器补取（响应头带分辨率/时长）
      if (!cachedDisk.hasMeta &&
          cachedDisk.durationSeconds == null &&
          serverCoverUrl != null &&
          _serverCoverSupported != false) {
        final result = await _fetchServerCover(serverCoverUrl);
        if (result != null) {
          final (thumb, status) = result;
          if (thumb != null) {
            _serverCoverSupported = true;
            final merged = VideoThumbnail(
              bytes: thumb.bytes ?? cachedDisk.bytes,
              width: thumb.width,
              height: thumb.height,
              durationSeconds: thumb.durationSeconds,
            );
            _memoryCache[videoUrl] = merged;
            _writeDiskCache(videoUrl, merged);
            return merged;
          }
          if (status == 404) {
            _serverCoverSupported = false;
          }
        }
      }
      _memoryCache[videoUrl] = cachedDisk;
      return cachedDisk;
    }

    // 4. 服务器封面优先（新服务器 ffmpeg 生成，移动端零解码）
    if (serverCoverUrl != null && _serverCoverSupported != false) {
      final result = await _fetchServerCover(serverCoverUrl);
      if (result != null) {
        final (thumb, status) = result;
        if (thumb != null) {
          _serverCoverSupported = true;
          _memoryCache[videoUrl] = thumb;
          _writeDiskCache(videoUrl, thumb);
          return thumb;
        }
        if (status == 404) {
          // 旧服务器无此接口，后续直接走本地生成
          _serverCoverSupported = false;
        }
        // 其他状态（500 等）：本文件生成失败，走本地回退
      }
    }

    // 5. 本地 mpv 生成（回退方案），创建任务并加入队列
    final completer = Completer<VideoThumbnail?>();
    _queue.add(_ThumbnailJob(videoUrl, completer));
    final future = completer.future;
    _pendingRequests[videoUrl] = future;

    // 触发队列处理
    _processQueue();

    try {
      final result = await future;
      if (result != null) {
        _memoryCache[videoUrl] = result;
        // 限制内存缓存大小
        if (_memoryCache.length > 100) {
          final keys = _memoryCache.keys.toList();
          for (int i = 0; i < 20; i++) {
            _memoryCache.remove(keys[i]);
          }
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

  /// 执行单个缩略图生成任务（顺带捕获宽高/时长）
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
      int? videoWidth;
      int? videoHeight;
      final startTime = DateTime.now();
      while (DateTime.now().difference(startTime) < _frameTimeout) {
        await Future.delayed(const Duration(milliseconds: 100));
        final w = player.state.width;
        final h = player.state.height;
        if (w != null && w > 0 && h != null && h > 0) {
          videoWidth = w;
          videoHeight = h;
          debugPrint(
              '[VideoThumbnail] Frame ready: ${w}x$h after ${DateTime.now().difference(startTime).inMilliseconds}ms');
          break;
        }
      }

      Uint8List? screenshot;
      if (videoWidth != null) {
        // 暂停并等待帧完全解码
        await player.pause();
        await Future.delayed(const Duration(milliseconds: 200));
        screenshot = await player.screenshot();

        if (screenshot != null) {
          screenshot = _compressThumbnail(screenshot);
          debugPrint(
              '[VideoThumbnail] Compressed: ${screenshot.length} bytes');
        }
      } else {
        debugPrint(
            '[VideoThumbnail] Timeout: ${DateTime.now().difference(startTime).inMilliseconds}ms');
      }

      // 捕获时长（停止前读取；vf 缩放不影响 state 尺寸）
      final duration = player.state.duration;
      final durationSeconds =
          duration.inMilliseconds > 0 ? duration.inMilliseconds / 1000 : null;

      // 停止播放释放资源
      await player.stop();

      final result = VideoThumbnail(
        bytes: screenshot,
        width: videoWidth,
        height: videoHeight,
        durationSeconds: durationSeconds,
      );
      // 持久化到磁盘缓存（异步，不阻塞后续播放）
      if (screenshot != null ||
          videoWidth != null ||
          durationSeconds != null) {
        _writeDiskCache(job.videoUrl, result);
      }

      _releasePlayer(pp);
      job.completer.complete(result);
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
  final Completer<VideoThumbnail?> completer;
  _ThumbnailJob(this.videoUrl, this.completer);
}
