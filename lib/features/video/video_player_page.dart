import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../core/models/file_info.dart';

/// 视频播放页
/// 支持触屏操作、键盘与 TV 遥控器（D-pad）操作
class VideoPlayerPage extends StatefulWidget {
  final FileInfo videoFile;
  final String baseUrl;

  const VideoPlayerPage({
    super.key,
    required this.videoFile,
    required this.baseUrl,
  });

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  late final Player _player;
  late final VideoController _controller;
  final FocusNode _focusNode = FocusNode();

  /// stream 订阅列表，dispose 时统一 cancel（避免泄漏持有 State）
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  bool _showControls = true;
  bool _isPlaying = false;
  bool _isBuffering = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _playbackSpeed = 1.0;
  bool _isFullscreen = false;
  double _volume = 100;

  /// 进度条拖动中的本地值（null 表示未拖动）
  double? _dragValue;

  /// 位置流节流：上次因 position 变化触发 setState 的时间
  DateTime _lastPositionNotify = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _initPlayer();
    _focusNode.requestFocus();
  }

  void _initPlayer() {
    _player = Player(
      configuration: const PlayerConfiguration(
        title: 'Video Player',
      ),
    );
    _controller = VideoController(_player);

    // Build the video stream URL
    final videoUrl =
        '${widget.baseUrl}/api/file?path=${Uri.encodeComponent(widget.videoFile.fullPath)}';

    // Open the video
    _player.open(Media(videoUrl));

    // Listen to player state changes
    _subscriptions.add(
      _player.stream.playing.listen((playing) {
        if (mounted) {
          setState(() {
            _isPlaying = playing;
          });
        }
      }),
    );

    _subscriptions.add(
      _player.stream.position.listen((position) {
        // 节流：播放中每 250ms 刷新一次 UI 即可，避免整页每 tick 重建
        _position = position;
        final now = DateTime.now();
        if (mounted &&
            now.difference(_lastPositionNotify) >= const Duration(milliseconds: 250)) {
          _lastPositionNotify = now;
          setState(() {});
        }
      }),
    );

    _subscriptions.add(
      _player.stream.duration.listen((duration) {
        if (mounted) {
          setState(() {
            _duration = duration;
          });
        }
      }),
    );

    _subscriptions.add(
      _player.stream.buffering.listen((buffering) {
        if (mounted) {
          setState(() {
            _isBuffering = buffering;
          });
        }
      }),
    );

    _subscriptions.add(
      _player.stream.completed.listen((completed) {
        if (completed) {
          WakelockPlus.disable();
        }
      }),
    );

    _subscriptions.add(
      _player.stream.volume.listen((volume) {
        if (mounted) {
          setState(() {
            _volume = volume;
          });
        }
      }),
    );

    // Keep screen awake while playing
    WakelockPlus.enable();
  }

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _focusNode.dispose();
    _player.dispose();
    WakelockPlus.disable();
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  void _togglePlayPause() {
    _player.playOrPause();
  }

  void _seekTo(Duration position) {
    _player.seek(position);
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  void _toggleFullscreen() {
    setState(() {
      _isFullscreen = !_isFullscreen;
    });
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      // 恢复全部方向，避免平板/TV 上被锁竖屏
      SystemChrome.setPreferredOrientations([]);
    }
  }

  void _cycleSpeed() {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    final currentIndex = speeds.indexOf(_playbackSpeed);
    final nextIndex = (currentIndex + 1) % speeds.length;
    _playbackSpeed = speeds[nextIndex];
    _player.setRate(_playbackSpeed);
    setState(() {});
  }

  void _seekRelative(Duration offset) {
    final newPosition = _position + offset;
    final clampedPosition = Duration(
      milliseconds: newPosition.inMilliseconds.clamp(
        0,
        _duration.inMilliseconds,
      ),
    );
    _seekTo(clampedPosition);
    setState(() {});
  }

  void _adjustVolume(double delta) {
    final newVolume = (_volume + delta).clamp(0.0, 100.0);
    _player.setVolume(newVolume);
  }

  /// 键盘 / 遥控器按键处理
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.mediaRewind) {
      _seekRelative(const Duration(seconds: -10));
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.mediaFastForward) {
      _seekRelative(const Duration(seconds: 10));
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _adjustVolume(5);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _adjustVolume(-5);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space) {
      _togglePlayPause();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.escape) {
      if (_isFullscreen) {
        _toggleFullscreen();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _isFullscreen
          ? null
          : AppBar(
              title: Text(
                widget.videoFile.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
            ),
      body: Focus(
        focusNode: _focusNode,
        onKeyEvent: _onKey,
        autofocus: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleControls,
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Video display
                    Video(
                      controller: _controller,
                      fit: BoxFit.contain,
                    ),
                    // Buffering indicator
                    if (_isBuffering)
                      const CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                  ],
                ),
              ),
              // 单一底部控制栏（进度 + 操作按钮）
              if (_showControls) _buildBottomControls(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    // 拖动中显示本地值，避免每帧 seek 造成网络请求风暴
    final double sliderValue = _dragValue ??
        (_duration.inMilliseconds > 0
            ? _position.inMilliseconds / _duration.inMilliseconds
            : 0.0);

    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Progress bar
          Row(
            children: [
              Text(
                _formatDuration(
                  Duration(
                    milliseconds:
                        (sliderValue * _duration.inMilliseconds).round(),
                  ),
                ),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              Expanded(
                child: Slider(
                  value: sliderValue.clamp(0.0, 1.0),
                  onChanged: (value) {
                    setState(() {
                      _dragValue = value;
                    });
                  },
                  onChangeStart: (value) {
                    setState(() {
                      _dragValue = value;
                    });
                  },
                  onChangeEnd: (value) {
                    final newPosition = Duration(
                      milliseconds: (value * _duration.inMilliseconds).round(),
                    );
                    _dragValue = null;
                    _seekTo(newPosition);
                  },
                  activeColor: Theme.of(context).colorScheme.primary,
                  inactiveColor: Colors.grey[600],
                ),
              ),
              Text(
                _formatDuration(_duration),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          // Action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Rewind 10s
              IconButton(
                icon: const Icon(Icons.replay_10, color: Colors.white, size: 30),
                onPressed: () => _seekRelative(const Duration(seconds: -10)),
              ),
              // Play/Pause
              IconButton(
                icon: Icon(
                  _isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 40,
                ),
                onPressed: _togglePlayPause,
              ),
              // Forward 10s
              IconButton(
                icon: const Icon(Icons.forward_10, color: Colors.white, size: 30),
                onPressed: () => _seekRelative(const Duration(seconds: 10)),
              ),
              const SizedBox(width: 24),
              // Speed
              TextButton(
                onPressed: _cycleSpeed,
                child: Text(
                  '${_playbackSpeed}x',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
              // Fullscreen
              IconButton(
                icon: Icon(
                  _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                  color: Colors.white,
                ),
                onPressed: _toggleFullscreen,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
