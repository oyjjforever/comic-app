import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

/// 视频缩略图生成服务
/// 使用 media_kit (libmpv) 直接从网络 URL 解码视频帧生成缩略图
/// libmpv 支持通过 HTTP 直接流式读取视频，无需完整下载
class VideoThumbnailService {
  VideoThumbnailService._();
  static final VideoThumbnailService instance = VideoThumbnailService._();

  // 内存缓存：videoUrl -> thumbnail bytes
  final Map<String, Uint8List?> _memoryCache = {};

  // 正在生成的请求去重
  final Map<String, Future<Uint8List?>> _pendingRequests = {};

  // 共享 Player 实例（用于所有缩略图生成）
  Player? _player;
  bool _playerReady = false;

  // 串行处理队列（避免并发操作同一个 Player）
  bool _processing = false;
  final List<_ThumbnailJob> _queue = [];

  /// 确保 Player 已初始化
  Future<Player> _ensurePlayer() async {
    if (_playerReady && _player != null) return _player!;

    final completer = Completer<void>();
    _player = Player(
      configuration: PlayerConfiguration(
        ready: () {
          if (!completer.isCompleted) completer.complete();
        },
      ),
    );
    await completer.future;

    // 配置 Player 用于缩略图生成：
    // 1. 启用视频解码（Player 默认 vid=no）
    // 2. 强制软件解码（Android 硬件解码需要 Surface，缩略图生成无 Surface）
    // 3. 禁用音频输出（缩略图不需要音频，节省资源）
    // 4. 缩小解码分辨率（加速解码，减小截图体积）
    final nativePlayer = _player!.platform as dynamic;
    await nativePlayer.setProperty('vid', 'auto');
    await nativePlayer.setProperty('hwdec', 'no');
    await nativePlayer.setProperty('ao', 'null');
    await nativePlayer.setProperty('vf', 'scale=320:-2');
    // 增大缓存以支持大文件 HTTP 流式读取
    await nativePlayer.setProperty('demuxer-max-bytes', '100MiB');
    await nativePlayer.setProperty('demuxer-max-back-bytes', '50MiB');
    // 忽略索引（对 moov atom 在末尾的 MP4，直接从文件头解码，无需先下载 moov）
    await nativePlayer.setProperty('demuxer-lavf-o', 'fflags=+ignidx');
    _playerReady = true;
    return _player!;
  }

  /// 获取视频缩略图
  Future<Uint8List?> getThumbnail(String videoUrl) async {
    // 1. 检查内存缓存
    if (_memoryCache.containsKey(videoUrl)) {
      return _memoryCache[videoUrl];
    }

    // 2. 检查是否有正在进行的请求（去重）
    if (_pendingRequests.containsKey(videoUrl)) {
      return _pendingRequests[videoUrl]!;
    }

    // 3. 创建任务并加入队列
    final completer = Completer<Uint8List?>();
    _queue.add(_ThumbnailJob(videoUrl, completer));
    final future = completer.future;
    _pendingRequests[videoUrl] = future;

    // 4. 触发队列处理
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

  /// 处理队列中的下一个任务
  void _processQueue() {
    if (_processing || _queue.isEmpty) return;
    _processing = true;
    final job = _queue.removeAt(0);
    _processJob(job).whenComplete(() {
      _processing = false;
      _processQueue();
    });
  }

  /// 执行单个缩略图生成任务（带重试）
  Future<void> _processJob(_ThumbnailJob job) async {
    try {
      final player = await _ensurePlayer();

      final shortUrl = job.videoUrl.length > 80
          ? '${job.videoUrl.substring(0, 80)}...'
          : job.videoUrl;
      debugPrint('[VideoThumbnail] Loading: $shortUrl');

      // 使用 play: true 加速帧解码（ao=null 已禁用音频）
      await player.open(Media(job.videoUrl), play: true);

      // 等待视频帧就绪（最多 15 秒，有些大文件需要较长时间）
      bool ready = false;
      for (int i = 0; i < 150; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        final w = player.state.width;
        final h = player.state.height;
        if (w != null && w > 0 && h != null && h > 0) {
          debugPrint(
              '[VideoThumbnail] Frame ready: ${w}x$h after ${(i + 1) * 100}ms');
          ready = true;
          break;
        }
      }

      Uint8List? screenshot;
      if (ready) {
        // 暂停播放（已经拿到帧了，不需要继续播放）
        await player.pause();
        // 等待确保帧完全解码
        await Future.delayed(const Duration(milliseconds: 300));
        screenshot = await player.screenshot();
        debugPrint('[VideoThumbnail] Screenshot: ${screenshot != null ? '${screenshot.length} bytes' : 'null'}');
      } else {
        debugPrint(
            '[VideoThumbnail] Timeout: width=${player.state.width}, duration=${player.state.duration}');
      }

      // 卸载视频（释放资源）
      await player.stop();

      // 如果第一次失败，重试一次（可能是网络延迟导致）
      if (!ready && screenshot == null) {
        debugPrint('[VideoThumbnail] Retrying: $shortUrl');
        await player.open(Media(job.videoUrl), play: true);
        for (int i = 0; i < 100; i++) {
          await Future.delayed(const Duration(milliseconds: 100));
          final w = player.state.width;
          if (w != null && w > 0) {
            ready = true;
            break;
          }
        }
        if (ready) {
          await player.pause();
          await Future.delayed(const Duration(milliseconds: 300));
          screenshot = await player.screenshot();
          debugPrint(
              '[VideoThumbnail] Retry screenshot: ${screenshot != null ? '${screenshot.length} bytes' : 'null'}');
        }
        await player.stop();
      }

      job.completer.complete(screenshot);
    } catch (e) {
      debugPrint('[VideoThumbnail] Error: $e');
      try {
        await _player?.stop();
      } catch (_) {}
      // 如果 Player 出错，重置状态
      if (e.toString().contains('disposed')) {
        await _resetPlayer();
      }
      job.completer.complete(null);
    }
  }

  /// 重置 Player 实例
  Future<void> _resetPlayer() async {
    try {
      _player?.dispose();
    } catch (_) {}
    _player = null;
    _playerReady = false;
  }

  /// 清除内存缓存
  void clearMemoryCache() {
    _memoryCache.clear();
  }

  /// 释放资源
  void dispose() {
    _player?.dispose();
    _player = null;
    _playerReady = false;
  }
}

/// 缩略图生成任务
class _ThumbnailJob {
  final String videoUrl;
  final Completer<Uint8List?> completer;
  _ThumbnailJob(this.videoUrl, this.completer);
}
